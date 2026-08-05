# Derivations for the headless session: patched gamescope, the private Sunshine
# portal frontend, and the setgid-`input` shim.
{
  pkgs,
  lib,
  inputs,
  cfg,
  # The resolved system Steam (lib/resolved-steam.nix): `programs.steam.package`
  # when programs.steam is enabled, else `pkgs.steam`. apps/steam maps
  # programs.steam.package to pkgs.steam; the user-profile Steam is a pure
  # `extraPkgs` override whose store name is unchanged, so this is
  # representative of every path the launcher can exec.
  steamPkg,
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

  # Marker group for the setgid-`input` bridge. The module adds every IceDOS
  # user to it (see icedos.nix), so all users of this feature can exec the
  # shim, while a stray local account cannot. Grants nothing by itself — only
  # the wrapper turns membership into gid `input`.
  inputBridgeGroup = "sunshine-headless";

  # Base gamescope for the session. pipewire-cursor.patch is applied ALWAYS: the
  # PipeWire capture (paint_pipewire) never composites the X cursor, so without it
  # the stream shows no cursor at all — core headless-session behaviour, not an
  # opt-in. It does force a local gamescope build even where the other patches are
  # off; the headless-input patch (new CHeadlessInputThread reading Sunshine's
  # inputtino passthrough devices) is gated on inputInjection — the thread is
  # inert unless HEADLESS_INPUT_* env filters are set, so stock behaviour is
  # preserved whenever it does build.
  gamescopeBase = pkgs.gamescope.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      ++ [ ./lib/pipewire-cursor.patch ]
      ++ lib.optionals inputInjection [ ./lib/headless-input.patch ];
  });

  # + HDR headless patches:
  # - pipewire-hdr-metadata.patch: advertise BT.2020/PQ on the output so the portal ->
  #   Sunshine detects and streams HDR.
  # - headless-hdr-colorimetry.patch: makes GetNativeColorimetry() report BT.2020/PQ when
  #   bHDR10 is true, so g_ColorMgmtLuts carry the correct HDR mapping + slider adjustments.
  gamescopeHdr = gamescopeBase.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      ++ lib.optionals colorManagement [ ./lib/pipewire-color-mgmt.patch ]
      ++ [
        ./lib/pipewire-hdr-metadata.patch
        ./lib/headless-hdr-colorimetry.patch
      ];

    # paint_pipewire now uses g_ColorMgmtLuts (dynamic, slider-aware) via the
    # pipewire-color-mgmt patch.  In HDR mode we override outputEncodingEOTF to
    # PQ, and pin the SDR->HDR mapping to our options.
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/steamcompmgr.cpp \
        --replace-fail 'frameInfo.outputEncodingEOTF   = EOTF_Gamma22;' \
                       'frameInfo.outputEncodingEOTF   = g_bOutputHDREnabled ? EOTF_PQ : EOTF_Gamma22;' \
        --replace-fail '.displayColorimetry = displaycolorimetry_2020,' \
                       '.sdrGamutWideness = ${toString sdrGamutWideness}, .flSDROnHDRBrightness = ${toString sdrContentNits}, .displayColorimetry = displaycolorimetry_2020,'
    '';
  });

  # When only colorManagement is on (no HDR), apply just the color-mgmt patch.
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

  # mangoApp overlay in the STREAM: gamescope's pipewire capture (paint_pipewire) paints only
  # the focus / override / steam-overlay windows — it never paints externalOverlayWindow, so
  # the mangoapp overlay reaches scanout but not the Sunshine pipewire stream. Two patches:
  #  1. paint the external overlay when opaque (mirrors paint_all's cv_paint_external_overlay_plane).
  #  2. paint_pipewire's repaint gate only re-renders when the focus/override window commits, so
  #     over a STATIC Steam UI (no game committing frames) the overlay is never (re)painted — it
  #     only shows in-game. Also skip the early-return whenever a visible external overlay exists,
  #     so mangoapp's own updates repaint the capture over the Steam UI too.
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

  # jovian's portal, patched for stream size, wrapped onto gamescope-0 and shipped
  # with its D-Bus service + .portal definition.
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

        # fix-stream-size.patch shells out to pw-cli to size the stream; the backend
        # is D-Bus-activated under the private bus's bare PATH, so make pw-cli
        # reachable here rather than relying on the caller's PATH. gamescopePkg (the
        # patched build this module actually runs) is exposed too so the backend's
        # gamescopectl version check sees a matching build.
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

  # Filename MUST be <XDG_CURRENT_DESKTOP>-portals.conf and MUST name the backend
  # per interface (UseIn alone isn't enough on this xdg-desktop-portal version).
  sunshinePortalConfig = pkgs.writeTextDir "xdg-desktop-portal/gamescope-portals.conf" ''
    [preferred]
    org.freedesktop.impl.portal.ScreenCast=gamescope
    org.freedesktop.impl.portal.Screenshot=gamescope
  '';

  # setgid-`input` payload (isolateVirtualControllers): a C shim that promotes egid
  # `input` to the real gid (so bwrap mirrors it into the sandbox), then execs its
  # args. Must be a binary — bash would drop the setgid egid. It refuses every
  # caller except root or members of the `sunshine-headless` marker group baked
  # below (the `input` group has no human members — the module's assertion
  # rejects any normal user in `input` — so the shim is the only path to it) and
  # only execs store binaries
  # whose name matches steam-<ver>[-bwrap] / gamescope-<ver> — a shape check
  # against accidental misuse (e.g. a stray `sunshine-headless-gid /bin/sh`), NOT
  # a provenance guarantee; the C header says exactly that. A TEST_MAIN
  # build asserts the target gate against the real ${gamescopePkg}/bin/gamescope
  # and ${steamPkg}/bin/steam during this derivation's build, so a regression
  # fails the build, not the system. (The gate run is guarded by
  # canExecute: on a cross build the target cannot be run here, so the shape
  # asserts compile but don't execute — the system still refuses at runtime.)
  gidExec = pkgs.runCommandCC "sunshine-headless-gid" { } ''
    $CC -O2 -Wall -DEXPECTED_GROUP='"${inputBridgeGroup}"' ${./lib/sunshine-headless-gid.c} -o $out
    $CC -O2 -Wall -DTEST_MAIN -DEXPECTED_GROUP='"${inputBridgeGroup}"' \
        -DSTEAM_VERSION='"${steamPkg.version}"' -DGAMESCOPE_VERSION='"${gamescopePkg.version}"' \
        ${./lib/sunshine-headless-gid.c} -o $TMPDIR/sunshine-headless-gid-test
    ${lib.optionalString (pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform) ''
      $TMPDIR/sunshine-headless-gid-test
      $TMPDIR/sunshine-headless-gid-test ${gamescopePkg}/bin/gamescope
      $TMPDIR/sunshine-headless-gid-test ${steamPkg}/bin/steam
      $TMPDIR/sunshine-headless-gid-test "steam-${steamPkg.version}"
    ''}
  '';

  # SteamOS mode "Switch to Desktop" shim: Steam's -steamos3 mode exposes a menu
  # entry that calls `steamos-session-select desktop`. This script intercepts that
  # call and shuts down the headless session cleanly via steam -shutdown.
  steamosSessionSelect = pkgs.writeShellScriptBin "steamos-session-select" ''
    exec steam -shutdown
  '';
in
{
  inherit
    gamescopePkg
    xdg-desktop-portal-gamescope
    sunshinePortalConfig
    gidExec
    steamosSessionSelect
    inputBridgeGroup
    ;
}
