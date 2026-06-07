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
  name = pname;
  pname = "eden";
  version = "0.2.1";

  appName = "dev.eden_emu.eden";
  desktopFile = "${appName}.desktop";
  icon = "${appName}.svg";

  edenAppimage = fetchurl {
    url = "https://git.eden-emu.dev/eden-emu/eden/releases/download/v${version}/Eden-Linux-v${version}-${build}-${compiledWith}.AppImage";

    hash =
      {
        aarch64 =
          {
            clang-pgo = "sha256-tk+SbL90/YcKObFElxCEMj2JXVGRm5HpBjKOf4G+oIc=";
            gcc-standard = "sha256-SUAU9nQBu759SNpxKNdpc0z5eGO/sjSdSM0qEYFz52k=";
          }
          .${compiledWith};

        amd64 =
          {
            clang-pgo = "sha256-eii/mIsGSIMZiXIr26qQqzE3G0A4CBmYE+DqfIslum0=";
            gcc-standard = "sha256-L65lg5fa8TwRgIKj62XWGmUZlnteIuZmd1a67PYADFo=";
          }
          .${compiledWith};

        legacy =
          {
            clang-pgo = "sha256-T/9/JNRfq7SvxlLxsIQeOhYVbyc6Og+QS3975gFmVRc=";
            gcc-standard = "sha256-IAOkCHU7lmOjy3IIAIXff+Xwm3gl9ULBoBrRI723yOI=";
          }
          .${compiledWith};

        rog-ally =
          {
            clang-pgo = "sha256-Ak3+MH9+W1ObNUm9kkX2txybqpzHRPMdWNMYGFfYX/w=";
            gcc-standard = "sha256-5y3aCN+fhB+qZjMYLBYQIuIhR8CphFPq3a6xHfzxVkU=";
          }
          .${compiledWith};

        steamdeck =
          {
            clang-pgo = "sha256-XMWzWKxkSbQAIbILokMLTRIwJzfbFcjL5bRs6aq4XOU=";
            gcc-standard = "sha256-JlFwZNcGNYP0KanLfuBnN8iYBYantj7zA94Wm1WbC1Y=";
          }
          .${compiledWith};
      }
      .${build};
  };

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
