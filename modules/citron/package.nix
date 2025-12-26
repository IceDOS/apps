{
  build ? "x86_64_v3",
  fetchurl,
  stdenvNoCC,
}:

let
  name = pname;
  pname = "citron";
  version = "0.12.25";
  commitHash = "01c042048";

  citronAppimage = fetchurl {
    url = "https://git.citron-emu.org/Citron/Emulator/releases/download/${version}/citron_stable-${commitHash}-linux-${build}.AppImage";

    hash =
      {
        aarch64 = "sha256-b5k+I40ZIxY5yjlOPTWLhe4+kW/JU8Xh5TnuEoeZFHk=";
        x86_64 = "sha256-2HhsSm4yavFlXt4q5UrLw209HzQFtQwbRhSwX3FLpPs=";
        x86_64_v3 = "sha256-G0yX6ZP6f9nDY41VS8k/UVduoTsZLFrAduA5mOD3OmY=";
      }
      .${build};
  };
in
stdenvNoCC.mkDerivation {
  inherit name;

  dontUnpack = true;

  installPhase =
    let
      appImagePath = "$out/lib/citron.AppImage";
      appName = "org.citron_emu.citron";
      desktopFile = "${appName}.desktop";
      desktopFilePath = "$out/share/applications/${desktopFile}";
      icon = "${appName}.svg";
      iconPath = "$out/share/applications/${icon}";
    in
    ''
      mkdir -p $out/lib

      cp ${citronAppimage} ${appImagePath}
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
