{
  build ? "amd64",
  compiledWith ? "clang-pgo",
  extractAppImage,
  fetchurl,
  installDesktopEntry,
  makeDesktopItem,
  stdenvNoCC,
}:

let
  # Pin refreshed by ./update.sh. Upstream is a self-hosted Gitea, not GitHub, and each
  # release ships one AppImage per (build, toolchain) pair — all ten are pinned so any
  # `build`/`compiledWith` combination stays buildable.
  source = builtins.fromJSON (builtins.readFile ./source.json);

  name = pname;
  pname = "eden";
  inherit (source) version;

  appName = "dev.eden_emu.eden";
  desktopFile = "${appName}.desktop";
  icon = "${appName}.svg";

  edenAppimage = fetchurl { inherit (source.builds.${build}.${compiledWith}) url hash; };

  desktopItem = makeDesktopItem {
    name = appName;
    desktopName = "Eden";
    comment = "Nintendo Switch emulator";
    exec = "/@out@/AppRun";
    icon = "/@out@/share/applications/${icon}";
    type = "Application";

    categories = [
      "Game"
      "Emulator"
    ];
  };
in
stdenvNoCC.mkDerivation {
  inherit name;

  dontUnpack = true;

  installPhase = ''
    ${extractAppImage {
      src = edenAppimage;
      preMove = "rm AppDir/lib";
    }}

    # `rm AppDir/lib` above drops the `lib -> shared/lib` symlink that
    # bin/qt.conf's `Prefix = ../lib/qt6` rides to reach the bundled Qt
    # plugins/QML. Repoint Prefix at the surviving `shared/lib` tree, else
    # Qt aborts with "Could not find the Qt platform plugin" (core dump).
    substituteInPlace $out/bin/qt.conf \
      --replace-fail "Prefix = ../lib/qt6" "Prefix = ../shared/lib/qt6"

    # AppImage sharun wrappers leak into systemPackages and shadow real
    # xdg-utils binaries, breaking link-open in every Electron app
    # (Signal Desktop, etc.). They are AppImage-internal helpers — eden does
    # not need them on the host PATH.
    rm -f $out/bin/xdg-open $out/bin/gio-launch-desktop

    ${installDesktopEntry { inherit desktopItem desktopFile icon; }}
  '';
}
