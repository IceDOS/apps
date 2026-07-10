# Derivations for the headless session: patched gamescope, the private Sunshine
# portal frontend, and the setgid-`input` shim.
{
  pkgs,
  inputs,
  cfg,
}:

let
  inherit (cfg) hdr sdrGamutWideness sdrContentNits;

  # Gamescope + a PipeWire HDR-metadata patch (advertise BT.2020/PQ on the output so
  # the portal → Sunshine detects and streams HDR).
  gamescopeHdr = pkgs.gamescope.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./lib/pipewire-hdr-metadata.patch
    ];

    # paint_pipewire captures with the hardcoded SDR screenshot profile, so the buffer
    # is Rec.709/Gamma2.2 even in HDR and the metadata patch mislabels it BT.2020/PQ
    # ("deep fried"). Follow gamescope's bHDRScreenshot path: when g_bOutputHDREnabled,
    # emit PQ + the HDR screenshot LUTs so pixels really are BT.2020/PQ, and pin the
    # SDR→HDR mapping to our options (only the Gamma22 input branch is touched).
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/steamcompmgr.cpp \
        --replace-fail 'frameInfo.outputEncodingEOTF   = EOTF_Gamma22;' \
                       'frameInfo.outputEncodingEOTF   = g_bOutputHDREnabled ? EOTF_PQ : EOTF_Gamma22;' \
        --replace-fail 'frameInfo.lut3D[nInputEOTF]     = g_ScreenshotColorMgmtLuts[nInputEOTF].vk_lut3d;' \
                       'frameInfo.lut3D[nInputEOTF]     = (g_bOutputHDREnabled ? g_ScreenshotColorMgmtLutsHDR : g_ScreenshotColorMgmtLuts)[nInputEOTF].vk_lut3d;' \
        --replace-fail 'frameInfo.shaperLut[nInputEOTF] = g_ScreenshotColorMgmtLuts[nInputEOTF].vk_lut1d;' \
                       'frameInfo.shaperLut[nInputEOTF] = (g_bOutputHDREnabled ? g_ScreenshotColorMgmtLutsHDR : g_ScreenshotColorMgmtLuts)[nInputEOTF].vk_lut1d;' \
        --replace-fail '.displayColorimetry = displaycolorimetry_2020,' \
                       '.sdrGamutWideness = ${toString sdrGamutWideness}, .flSDROnHDRBrightness = ${toString sdrContentNits}, .displayColorimetry = displaycolorimetry_2020,'
    '';
  });

  # The HDR override is inert unless gamescope enters HDR (all edits gate on
  # g_bOutputHDREnabled), so SDR-only uses stock (cached) gamescope.
  gamescopePkg = if hdr then gamescopeHdr else pkgs.gamescope;

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
in
{
  inherit
    gamescopePkg
    xdg-desktop-portal-gamescope
    sunshinePortalConfig
    gidExec
    ;
}
