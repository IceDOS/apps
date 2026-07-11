# Derivations for the headless session: patched gamescope, the private Sunshine
# portal frontend, and the setgid-`input` shim.
{
  pkgs,
  lib,
  inputs,
  cfg,
}:

let
  inherit (cfg)
    hdr
    colorManagement
    sdrGamutWideness
    sdrContentNits
    ;

  # No patches needed when both hdr and colorManagement are off.
  gamescopeBase = pkgs.gamescope;

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

  gamescopePkg =
    if hdr then
      gamescopeHdr
    else if colorManagement then
      gamescopeColorMgmt
    else
      gamescopeBase;

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

        makeWrapper ${portalPkg}/libexec/xdg-desktop-portal-gamescope \
          $out/libexec/xdg-desktop-portal-gamescope \
          --set WAYLAND_DISPLAY gamescope-0

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
  # args. Must be a binary — bash would drop the setgid egid.
  gidExec = pkgs.runCommandCC "sunshine-headless-gid" { } ''
    $CC -O2 -Wall ${./lib/sunshine-headless-gid.c} -o $out
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
    ;
}
