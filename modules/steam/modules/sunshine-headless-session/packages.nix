# Derivations for the headless session: patched gamescope, the private Sunshine
# portal frontend, and the setgid-`input` shim.
{
  pkgs,
  lib,
  inputs,
  cfg,
  # The resolved system Steam (`programs.steam.package` when enabled, else
  # pkgs.steam): representative of every path the launcher can exec.
  steamPkg,
  # The headless daemon's Sunshine (pkgs.sunshine, same as daemon.nix), for the
  # bridge's sunshine-<ver> target shape.
  sunshinePkg,
}:

let
  inherit (cfg)
    hdr
    colorManagement
    inputInjection
    mangoApp
    sdrGamutWideness
    sdrContentNits
    ;

  # Marker group for the input bridge: every IceDOS user gets it, so all can exec
  # the shim; it grants nothing by itself — only the wrapper turns it into `input`.
  inputBridgeGroup = "sunshine-headless";

  # Base gamescope. pipewire-cursor.patch is ALWAYS applied (the capture never
  # composites the X cursor); the headless-input patch is gated on inputInjection.
  gamescopeBase = pkgs.gamescope.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      ++ [ ./lib/pipewire-cursor.patch ]
      ++ lib.optionals inputInjection [ ./lib/headless-input.patch ];
  });

  # + HDR headless patches (pipewire-hdr-metadata, headless-hdr-colorimetry):
  # advertise BT.2020/PQ on the output and report it from GetNativeColorimetry.
  gamescopeHdr = gamescopeBase.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      ++ lib.optionals colorManagement [ ./lib/pipewire-color-mgmt.patch ]
      ++ [
        ./lib/pipewire-hdr-metadata.patch
        ./lib/headless-hdr-colorimetry.patch
      ];

    # HDR overrides outputEncodingEOTF to PQ and pins the SDR->HDR mapping via g_ColorMgmtLuts.
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/steamcompmgr.cpp \
        --replace-fail 'frameInfo.outputEncodingEOTF   = EOTF_Gamma22;' \
                       'frameInfo.outputEncodingEOTF   = g_bOutputHDREnabled ? EOTF_PQ : EOTF_Gamma22;' \
        --replace-fail '.displayColorimetry = displaycolorimetry_2020,' \
                       '.sdrGamutWideness = ${toString sdrGamutWideness}, .flSDROnHDRBrightness = ${toString sdrContentNits}, .displayColorimetry = displaycolorimetry_2020,'
    '';
  });

  gamescopeColorMgmt = gamescopeBase.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./lib/pipewire-color-mgmt.patch
    ];
  });

  gamescopeSelected =
    if hdr then
      gamescopeHdr
    else if colorManagement then
      gamescopeColorMgmt
    else
      gamescopeBase;

  # Paint mangoapp's external overlay into the pipewire stream (scanout-only otherwise),
  # and repaint it over static Steam UI too (the focus/override repaint gate misses it).
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

  # Jovian's portal, patched for stream size, wrapped onto gamescope-0 with its
  # D-Bus service + .portal definition.
  xdg-desktop-portal-gamescope =
    let
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

        # fix-stream-size shells out to pw-cli; make it (and the matching gamescopePkg)
        # reachable under the private bus's bare PATH.
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

  # Filename MUST be <XDG_CURRENT_DESKTOP>-portals.conf and name the backend per interface.
  sunshinePortalConfig = pkgs.writeTextDir "xdg-desktop-portal/gamescope-portals.conf" ''
    [preferred]
    org.freedesktop.impl.portal.ScreenCast=gamescope
    org.freedesktop.impl.portal.Screenshot=gamescope
  '';

  # The input-bridge shim (see lib/sunshine-headless-gid.c): gated exec of
  # steam/gamescope/sunshine store binaries; TEST_MAIN asserts the gates at build time.
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

  # -steamos3 "Switch to Desktop": intercept steamos-session-select desktop and
  # shut the headless session down cleanly via steam -shutdown.
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
