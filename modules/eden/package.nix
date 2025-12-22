{
  build ? "amd64",
  compiledWith ? "clang-pgo",
  fetchurl,
  stdenvNoCC,
}:

let
  name = pname;
  pname = "eden";
  version = "0.0.4";

  edenAppimage = fetchurl {
    url = "https://git.eden-emu.dev/eden-emu/eden/releases/download/v${version}/Eden-Linux-v${version}-${build}-${compiledWith}.AppImage";

    hash =
      {
        aarch64 =
          {
            clang-pgo = "sha256-Qg0NupeJFHKgboyZFO3cPTPN1+ajQ6Eh4JiaN2S8rOQ=";
            gcc-standard = "sha256-gw+W8+XhliKrCHsDn5lAuoITupm8LBQfBmDbdWsLi2w=";
          }
          .${compiledWith};

        amd64 =
          {
            clang-pgo = "sha256-60nVaANf1tp5u8nvpCFhxgls/dX0W1hEKJUCppZswfQ=";
            gcc-standard = "sha256-7ZgPXuhF2MWlj3FDwaP74rfRgfbRI43Hw6qvdrzxMdQ=";
          }
          .${compiledWith};

        legacy =
          {
            clang-pgo = "sha256-krFLdBRkHGxq26a+/+95Q4Y5HiaYZia5IzkeBHjZ/Ug=";
            gcc-standard = "sha256-Q8UnQZHAPzCrRGPZUUi/m5XyYrNZnyJP/vJo4ThDBBM=";
          }
          .${compiledWith};

        rog-ally =
          {
            clang-pgo = "sha256-UZuj1VF6I1FK/QZc4jaNRfZ9GTFcQv1mjrz3dSvYfZ0=";
            gcc-standard = "sha256-tz6lETWK/aYehdlxHN2cS2PcZrGdMa97Ppvf7wMHmv4=";
          }
          .${compiledWith};

        steamdeck =
          {
            clang-pgo = "sha256-bjxl+0BQKKW69JoduwbWa2H6kkjNNqP2Ef4jf5kw9gw=";
            gcc-standard = "sha256-vs+DwcHLITlP+SdguSMWDt1/DTvmC3KGxw82aFri3cE=";
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
