{
  build ? "amd64",
  compiledWith ? "clang-pgo",
  fetchurl,
  stdenvNoCC,
}:

let
  name = pname;
  pname = "eden";
  version = "0.1.1";

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
in
stdenvNoCC.mkDerivation {
  inherit name;

  dontUnpack = true;

  installPhase =
    let
      appImagePath = "$out/lib/eden.AppImage";
      appName = "dev.eden_emu.eden";
      desktopFile = "${appName}.desktop";
      desktopFilePath = "$out/share/applications/${desktopFile}";
      icon = "${appName}.svg";
      iconPath = "$out/share/applications/${icon}";
    in
    ''
      mkdir -p $out/lib

      cp ${edenAppimage} ${appImagePath}
      chmod +x ${appImagePath}
      ${appImagePath} --appimage-extract
      rm ${appImagePath}
      rm AppDir/lib
      mv AppDir/* $out

      mkdir -p $out/share/applications
      ln -s $out/${desktopFile} ${desktopFilePath}
      ln -s $out/${icon} ${iconPath}

      substituteInPlace ${desktopFilePath} --replace-fail "${appName}" "${iconPath}"
    '';
}
