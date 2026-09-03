# Derivations for the headless session: patched gamescope, the private Sunshine
# portal frontend, and the setgid-`input` shim.
{
  pkgs,
  lib,
  inputs,
  cfg,
  # The resolved system Steam (programs.steam.package when enabled, else an FHS env
  # carrying programs.steam.extraPackages so launch-option helpers exist in /usr).
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
    nativeWayland
    steamOS
    preferDiscreteGpu
    sdrGamutWideness
    sdrContentNits
    ;

  # Marker group for the input bridge; the wrapper alone turns it into `input` access.
  inputBridgeGroup = "sunshine-headless";

  # Every patch is gated by its own option (each forces a local rebuild). PR refs: #2271, #2217, #2270.
  # Bespoke native-wayland.patch has no upstream PR; gamescopePkg always adds a Steam-overlay postPatch.
  anyGamescopePatch =
    preferDiscreteGpu || inputInjection || (nativeWayland && steamOS) || hdr || colorManagement;

  gamescopePatched = pkgs.gamescope.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      ++ lib.optionals preferDiscreteGpu [ ./lib/prefer-discrete-gpu.patch ]
      # nativeWayland works only in SteamOS mode (baselayer driver is in the steamos
      # wait-loop branch), so the patch applies there only; non-steamOS keeps stock.
      ++ lib.optionals (nativeWayland && steamOS) [ ./lib/native-wayland.patch ]
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

  # Always paint the Steam overlay into the stream when visible: upstream gates overlayWindow
  # painting on !ulFocusAppId, so a focused game hides the Big Picture overlay from capture.
  gamescopePkg = gamescopeSelected.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
                substituteInPlace src/steamcompmgr.cpp \
                  --replace-fail '!ulFocusAppId && pFocus->overlayWindow && pFocus->overlayWindow->opacity' 'pFocus->overlayWindow && pFocus->overlayWindow->opacity'

                # paint_pipewire() focuses a synthetic window that never sets overlayWindow; copy it
                # from the real global focus so the overlay paint conditions above can find the window.
                substituteInPlace src/steamcompmgr.cpp \
                  --replace-fail 'pick_primary_focus_and_override( &s_PipewireFocus, None, vecPossibleFocusWindows, false, vecAppIds, 0, gamescope::VirtualConnectorStrategies::SteamControlled );' \
                                  'pick_primary_focus_and_override( &s_PipewireFocus, None, vecPossibleFocusWindows, false, vecAppIds, 0, gamescope::VirtualConnectorStrategies::SteamControlled );
         			if ( focus_t *pGlobalFocus = GetCurrentFocus() )
         			{
        				s_PipewireFocus.overlayWindow = pGlobalFocus->overlayWindow;
        				s_PipewireFocus.externalOverlayWindow = pGlobalFocus->externalOverlayWindow;
         			}'

                # Skip the early return when the overlay is visible (overlayWindow && opacity>0) so
                # open/close repaints; anchored on a line stable across the inputInjection patch.
                substituteInPlace src/steamcompmgr.cpp \
                  --replace-fail 'if ( ulFocusCommitId == s_ulLastFocusCommitId &&' \
                                  'if ( !( pFocus->overlayWindow && pFocus->overlayWindow->opacity ) && ulFocusCommitId == s_ulLastFocusCommitId &&'
      ''
      + lib.optionalString mangoApp ''
        substituteInPlace src/steamcompmgr.cpp \
          --replace-fail 'gamescope::Rc<CVulkanTexture> pRGBTexture = s_pPipewireBuffer->texture->isYcbcr()' 'if ( global_focus_t *pMangoOverlayFocus = GetCurrentFocus() ) { if ( pMangoOverlayFocus->externalOverlayWindow && pMangoOverlayFocus->externalOverlayWindow->opacity ) paint_window( pMangoOverlayFocus->externalOverlayWindow, pMangoOverlayFocus->externalOverlayWindow, &frameInfo, nullptr, PaintWindowFlag::NoScale | PaintWindowFlag::NoFilter | ( cv_overlay_unmultiplied_alpha ? PaintWindowFlag::CoverageMode : 0 ) ); } gamescope::Rc<CVulkanTexture> pRGBTexture = s_pPipewireBuffer->texture->isYcbcr()' \
          --replace-fail 'ulOverrideCommitId == s_ulLastOverrideCommitId &&' 'ulOverrideCommitId == s_ulLastOverrideCommitId && !( GetCurrentFocus() && GetCurrentFocus()->externalOverlayWindow && GetCurrentFocus()->externalOverlayWindow->opacity ) &&'
      '';
  });

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

        # printf, not a heredoc: Nix strips indentation, so an indented EOF never terminates.
        printf '%s\n' \
          '[D-BUS Service]' \
          'Name=org.freedesktop.impl.portal.desktop.gamescope' \
          "Exec=$out/libexec/xdg-desktop-portal-gamescope" \
          > $out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.gamescope.service

        printf '%s\n' \
          '[portal]' \
          'DBusName=org.freedesktop.impl.portal.desktop.gamescope' \
          'Interfaces=org.freedesktop.impl.portal.Access;org.freedesktop.impl.portal.ScreenCast;org.freedesktop.impl.portal.Screenshot;' \
          'UseIn=gamescope' \
          > $out/share/xdg-desktop-portal/portals/gamescope.portal
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
