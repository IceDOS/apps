{
  build ? "amd64",
  fetchurl,
  stdenvNoCC,
}:

let
  name = pname;
  pname = "eden";
  version = "0.0.3";

  edenAppimage = fetchurl {
    url = "https://github.com/eden-emulator/Releases/releases/download/v${version}/Eden-Linux-v${version}-${build}.AppImage";
    hash =
      {
        amd64 = "sha256-P2Qy1VdSvKXvPNJKzzIzLxMumS5BQ79bOC0FTgFHMiw=";
        legacy = "sha256-/FQT22Effl/Q1sWv0tdbXAKQOky+aju19CPBTv+cHNY=";
        rog-ally = "sha256-eTM+vx9L7GjYUD4c4IyU1wVn5dib/pnMDHKJiS5+m7U=";
        steamdeck = "sha256-8EB1X/kkx3hOTzbJC0geOH/YpH1wFY5MyxkoKYwXmF4=";
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
      edenBin = "$out/bin/eden";
      edenLibRun = "$out/lib/AppRun";
      desktopFile = "${appName}.desktop";
      desktopFilePath = "$out/share/applications/${desktopFile}";
      icon = "${appName}.svg";
      iconPath = "$out/share/applications/${icon}";
    in
    ''
      mkdir -p $out/lib $out/bin $out/share/applications

      cp ${edenAppimage} ${appImagePath}
      chmod +x ${appImagePath}
      ${appImagePath} --appimage-extract
      rm ${appImagePath}
      mv AppDir/* $out/lib
      rm -r AppDir squashfs-root

      ln -s $out/lib/${desktopFile} ${desktopFilePath}
      ln -s $out/lib/${icon} ${iconPath}

      substituteInPlace ${desktopFilePath} --replace-fail "${appName}" "${iconPath}"

      ln -s ${edenLibRun} ${edenBin}
      chmod +x ${edenBin}
    '';
}
