{
  build ? "amd64",
  compiledWith ? "clang-pgo",
  fetchurl,
  makeDesktopItem,
  stdenvNoCC,
}:

let
  name = pname;
  pname = "eden";
  version = "0.1.1";

  appName = "dev.eden_emu.eden";
  desktopFile = "${appName}.desktop";
  icon = "${appName}.svg";

  edenAppimage = fetchurl {
    url = "https://git.eden-emu.dev/eden-emu/eden/releases/download/v${version}/Eden-Linux-v${version}-${build}-${compiledWith}.AppImage";

    hash =
      {
        aarch64 =
          {
            clang-pgo = "sha256-6iU5RV5gogxpJUFwWi0p2y4r8IRvAcuxSwcpCIWsG6E=";
            gcc-standard = "sha256-WzwWpxJm1UzSI2IgpjwFzJ/9Z5DgivxtQLhfyFquHZ4=";
          }
          .${compiledWith};

        amd64 =
          {
            clang-pgo = "sha256-g7x10zM/55z2avdETcpRJ56O1oN8cndbzl9UAiOJZF8=";
            gcc-standard = "sha256-B3iU8SmwI44hUmbfFuSKQWriemulIXoRJF0atBfioeg=";
          }
          .${compiledWith};

        legacy =
          {
            clang-pgo = "sha256-sArRWvGMEdgJ3JfL/aPXbKbwQS/CE8DSoQS1qu27zsw=";
            gcc-standard = "sha256-QXMPtplqhtS8qgVnXFpcILRLOCNynVBvvZKDR3FwpJI=";
          }
          .${compiledWith};

        rog-ally =
          {
            clang-pgo = "sha256-F0dVNkaiDTR/f8T8A2x7Id5pA+vr9EnU9njEERObcPw=";
            gcc-standard = "sha256-UI0kYWaAZLFGuATcL6GqSajov0ahy4tPNpf2o/EMst0=";
          }
          .${compiledWith};

        steamdeck =
          {
            clang-pgo = "sha256-TSqAXu6nZElt6jTyy7NCU6YGmhwlWvucEzDuB5wNShM=";
            gcc-standard = "sha256-XV/Tl/jx1iEypJN+qx9llyZ8gVQVlyoA4FqJ5HsGBsY=";
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
    mkdir -p $out/lib

    cp ${edenAppimage} $out/lib/eden.AppImage
    chmod +x $out/lib/eden.AppImage
    $out/lib/eden.AppImage --appimage-extract
    rm $out/lib/eden.AppImage
    rm AppDir/lib
    mv AppDir/* $out

    # AppImage sharun wrappers leak into systemPackages and shadow real
    # xdg-utils binaries, breaking link-open in every Electron app
    # (Signal Desktop, etc.). They are AppImage-internal helpers — eden does
    # not need them on the host PATH.
    rm -f $out/bin/xdg-open $out/bin/gio-launch-desktop

    install -Dm644 ${desktopItem}/share/applications/${desktopFile} \
      $out/share/applications/${desktopFile}
    substituteInPlace $out/share/applications/${desktopFile} \
      --replace-fail "/@out@" "$out"

    ln -s $out/${icon} $out/share/applications/${icon}
  '';
}
