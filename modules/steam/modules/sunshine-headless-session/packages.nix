# Derivations for the headless session: patched gamescope, the private Sunshine
# portal frontend, and the setgid-`input` shim.
{
  pkgs,
  lib,
  inputs,
  cfg,
  # The resolved system Steam (programs.steam.package when enabled, else pkgs.steam).
  steamPkg,
  # The headless daemon's Sunshine (pkgs.sunshine, same as daemon.nix).
  sunshinePkg,
}:

let
  inherit (cfg)
    hdr
    colorManagement
    inputInjection
    mangoApp
    nv12BlackFrameFix
    preferDiscreteGpu
    sdrGamutWideness
    sdrContentNits
    ;

  # Marker group for the input bridge; the wrapper alone turns it into `input` access.
  inputBridgeGroup = "sunshine-headless";

  # Every patch is gated behind its own option (each forces a local rebuild); all off
  # = stock gamescope. PR refs: #2271 (bSampled), #2217 (discrete GPU), #2270 (HDR LUTs).
  anyGamescopePatch =
    nv12BlackFrameFix
    || preferDiscreteGpu
    || inputInjection
    || hdr
    || colorManagement;

  gamescopePatched = pkgs.gamescope.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      ++ lib.optionals nv12BlackFrameFix [ ./lib/pipewire-bsampled.patch ]
      ++ lib.optionals preferDiscreteGpu [ ./lib/prefer-discrete-gpu.patch ]
      ++ lib.optionals inputInjection [
        ./lib/pipewire-cursor.patch
        ./lib/headless-input.patch
      ]
      ++ lib.optionals (hdr || colorManagement) [ ./lib/pipewire-paint-hdr-luts.patch ]
      ++ lib.optionals colorManagement [ ./lib/pipewire-color-mgmt.patch ]
      ++ lib.optionals hdr [
        ./lib/pipewire-hdr-metadata.patch
        ./lib/headless-hdr-colorimetry.patch
      ];

    # HDR: paint PQ (outputEncodingEOTF) and pin the SDR->HDR mapping (k_ScreenshotColorMgmtHDR).
    postPatch =
      (old.postPatch or "")
      + lib.optionalString hdr ''
        substituteInPlace src/steamcompmgr.cpp \
          --replace-fail 'frameInfo.outputEncodingEOTF   = EOTF_Gamma22;' \
                         'frameInfo.outputEncodingEOTF   = g_bOutputHDREnabled ? EOTF_PQ : EOTF_Gamma22;' \
          --replace-fail '.displayColorimetry = displaycolorimetry_2020,' \
                         '.sdrGamutWideness = ${toString sdrGamutWideness}, .flSDROnHDRBrightness = ${toString sdrContentNits}, .displayColorimetry = displaycolorimetry_2020,'
      '';
  });

  gamescopeSelected = if anyGamescopePatch then gamescopePatched else pkgs.gamescope;

  # Repaint mangoapp's overlay into the pipewire stream (scanout-only otherwise),
  # incl. static Steam UI (the focus/override repaint gate misses it).
  gamescopePkg =
    if mangoApp then
      gamescopeSelected.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/steamcompmgr.cpp \
            --replace-fail 'gamescope::Rc<CVulkanTexture> pRGBTexture = s_pPipewireBuffer->texture->isYcbcr()' 'if ( global_focus_t *pMangoOverlayFocus = GetCurrentFocus() ) { if ( pMangoOverlayFocus->externalOverlayWindow && pMangoOverlayFocus->externalOverlayWindow->opacity ) paint_window( pMangoOverlayFocus->externalOverlayWindow, pMangoOverlayFocus->externalOverlayWindow, &frameInfo, nullptr, PaintWindowFlag::NoScale | PaintWindowFlag::NoFilter | ( cv_overlay_unmultiplied_alpha ? PaintWindowFlag::CoverageMode : 0 ) ); } gamescope::Rc<CVulkanTexture> pRGBTexture = s_pPipewireBuffer->texture->isYcbcr()' \
            --replace-fail 'ulOverrideCommitId == s_ulLastOverrideCommitId &&' 'ulOverrideCommitId == s_ulLastOverrideCommitId && !( GetCurrentFocus() && GetCurrentFocus()->externalOverlayWindow && GetCurrentFocus()->externalOverlayWindow->opacity ) &&'
        '';
      })
    else
      gamescopeSelected;

  # Jovian's portal, patched for stream size, wrapped onto gamescope-0 (private D-Bus).
  xdg-desktop-portal-gamescope =
    let
      # REQUIRED, always applied: without it the 1.22+ portal frontend forwards 0x0
      # to the client and Sunshine's startup probe wedges.
      portalPkg =
        (inputs.jovian.overlays.default pkgs pkgs).xdg-desktop-portal-gamescope.overrideAttrs
          (old: {
            patches = (old.patches or [ ]) ++ [
              ./lib/fix-stream-size.patch
            ];
          });
    in
    pkgs.runCommand "xdg-desktop-portal-gamescope-portal"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
              mkdir -p $out/share/dbus-1/services
              mkdir -p $out/share/xdg-desktop-portal/portals
              mkdir -p $out/libexec

        # fix-stream-size shells out to pw-cli; put it + gamescopePkg on the bare PATH.
              makeWrapper ${portalPkg}/libexec/xdg-desktop-portal-gamescope \
                $out/libexec/xdg-desktop-portal-gamescope \
                --set WAYLAND_DISPLAY gamescope-0 \
                --prefix PATH : ${pkgs.pipewire}/bin \
                --prefix PATH : ${gamescopePkg}/bin

              cat > $out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.gamescope.service << EOF
              [D-BUS Service]
              Name=org.freedesktop.impl.portal.desktop.gamescope
              Exec=$out/libexec/xdg-desktop-portal-gamescope
              EOF

              cat > $out/share/xdg-desktop-portal/portals/gamescope.portal << EOF
              [portal]
              DBusName=org.freedesktop.impl.portal.desktop.gamescope
              Interfaces=org.freedesktop.impl.portal.Access;org.freedesktop.impl.portal.ScreenCast;org.freedesktop.impl.portal.Screenshot;
              UseIn=gamescope
              EOF
      '';

  # Filename MUST be <XDG_CURRENT_DESKTOP>-portals.conf, naming the backend per interface.
  sunshinePortalConfig = pkgs.writeTextDir "xdg-desktop-portal/gamescope-portals.conf" ''
    [preferred]
    org.freedesktop.impl.portal.ScreenCast=gamescope
    org.freedesktop.impl.portal.Screenshot=gamescope
  '';

  # The input-bridge shim (lib/sunshine-headless-gid.c): gated exec of steam/gamescope/sunshine.
  gidExec = pkgs.runCommandCC "sunshine-headless-gid" { } ''
    $CC -O2 -Wall -DEXPECTED_GROUP='"${inputBridgeGroup}"' -DINPUT_GROUP='"input"' \
        ${./lib/sunshine-headless-gid.c} -o $out
    $CC -O2 -Wall -DTEST_MAIN -DEXPECTED_GROUP='"${inputBridgeGroup}"' -DINPUT_GROUP='"input"' \
        -DSTEAM_VERSION='"${steamPkg.version}"' -DGAMESCOPE_VERSION='"${gamescopePkg.version}"' \
        -DSUNSHINE_VERSION='"${sunshinePkg.version}"' \
        ${./lib/sunshine-headless-gid.c} -o $TMPDIR/sunshine-headless-gid-test
    ${lib.optionalString (pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform) ''
      $TMPDIR/sunshine-headless-gid-test
      $TMPDIR/sunshine-headless-gid-test ${gamescopePkg}/bin/gamescope
      $TMPDIR/sunshine-headless-gid-test ${steamPkg}/bin/steam
      $TMPDIR/sunshine-headless-gid-test ${sunshinePkg}/bin/sunshine
      $TMPDIR/sunshine-headless-gid-test "steam-${steamPkg.version}"
      $TMPDIR/sunshine-headless-gid-test "sunshine-${sunshinePkg.version}"
    ''}
  '';

  # -steamos3 "Switch to Desktop": shut the headless session down via steam -shutdown.
  steamosSessionSelect = pkgs.writeShellScriptBin "steamos-session-select" ''
    exec steam -shutdown
  '';
in
{
  inherit
    gamescopePkg
    steamPkg
    xdg-desktop-portal-gamescope
    sunshinePortalConfig
    gidExec
    steamosSessionSelect
    inputBridgeGroup
    ;
}
