{
  build ? "amd64",
  compiledWith ? "clang-pgo",
  fetchurl,
  stdenvNoCC,
}:

let
  name = pname;
  pname = "eden";
  version = "0.0.4-rc3";

  edenAppimage = fetchurl {
    url = "https://git.eden-emu.dev/eden-emu/eden/releases/download/v${version}/Eden-Linux-v${version}-${build}-${compiledWith}.AppImage";

    hash =
      {
        aarch64 =
          {
            clang-pgo = "sha256-TlhO8YELRiVno+IHLtsHraIjhzkixfQIMvqhsU+aHak=";
            gcc-standard = "sha256-xXCtHq/7Mtl1XFAD2uSGCJYWPp1bYuPkyaUa5PmnVaw=";
          }
          .${compiledWith};

        amd64 =
          {
            clang-pgo = "sha256-nV2y75tqVJ+OunTN3TF8K7JyssE4vApY9Vn4Fh5IczY=";
            gcc-standard = "sha256-G+sTFtw8cVO/Vj1aSSS07Uy6GQXoQDufrbvoskz9cqg=";
          }
          .${compiledWith};

        legacy =
          {
            clang-pgo = "sha256-l5WEVwt9CaBGJY5yeGRbHL1CNFHQXnw4TlM2aoyVCSw=";
            gcc-standard = "sha256-rhQpZgZ3+TzQud+KNd0tN7HDUxN6jd5fmGpIeZfOdXA=";
          }
          .${compiledWith};

        rog-ally =
          {
            clang-pgo = "sha256-YWOoVji4Z2h/HRswAP8vPt6KmAUPORPW2XibBrf0gKk=";
            gcc-standard = "sha256-DNNgfdGNpAdrfrBpjlKhxo3JW+WZgmTjAOhCLjWCgc4=";
          }
          .${compiledWith};

        steamdeck =
          {
            clang-pgo = "sha256-SK2Q+NNeGq7EOjyYE4KEfiFK1TD9v4uNyh5KtFkzm/A=";
            gcc-standard = "sha256-fPoTuZwUaH0qLnMy1yzCAboj1ZYU4rgDwqtdYNpD8RA=";
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
