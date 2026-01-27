{
  build ? "amd64",
  compiledWith ? "clang-pgo",
  fetchurl,
  stdenvNoCC,
}:

let
  name = pname;
  pname = "eden";
  version = "0.1.0";

  edenAppimage = fetchurl {
    url = "https://git.eden-emu.dev/eden-emu/eden/releases/download/v${version}/Eden-Linux-v${version}-${build}-${compiledWith}.AppImage";

    hash =
      {
        aarch64 =
          {
            clang-pgo = "sha256-KDYSvNknaApwDQXflb/Y1zhjWKhZsBOSfYRQPRCJI0M=";
            gcc-standard = "sha256-KEIAc6rHUU90kcoIUhLWkylGenRWPI7qFc5fQNyRPyg=";
          }
          .${compiledWith};

        amd64 =
          {
            clang-pgo = "sha256-+1lBCtlau8ttdy2olhNvlir/bn/sSpUz+6Ofo+GZ0dg=";
            gcc-standard = "sha256-0QOGVTSildzRHcFNL15j2alDK6/DUHiFUKHS/JifZEE=";
          }
          .${compiledWith};

        legacy =
          {
            clang-pgo = "sha256-kgzfHSinWcwTJk+HZwz5FvNNOzUG3iExcQYb2qxfnN4=";
            gcc-standard = "sha256-7RIXJDNH5dVG7cT4TadrzoFWijt2K/Jy7vFffj0/F10=";
          }
          .${compiledWith};

        rog-ally =
          {
            clang-pgo = "sha256-UsGMjjJTdB4hzeSyIrN6aAgrckExgcxKVrdZz5mkhqo=";
            gcc-standard = "sha256-ubnfRGREw/W1OjoMN9vjEXCDjFmNdU9P1hGfxR2Tmt8=";
          }
          .${compiledWith};

        steamdeck =
          {
            clang-pgo = "sha256-n8xlLPoRxxHwlICf2QYU7iLVxq2EnRwG1de7gLwdOOY=";
            gcc-standard = "sha256-XmYGtyIX8Rq/ugZdhHyZget9UghUZar4abtYVZtSDvU=";
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
