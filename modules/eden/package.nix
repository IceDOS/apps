{
  build ? "amd64",
  fetchurl,
  stdenvNoCC,
}:

let
  name = pname;
  pname = "eden";
  version = "0.0.3-rc3";

  edenAppimage = fetchurl {
    url = "https://github.com/eden-emulator/Releases/releases/download/v${version}/Eden-Linux-v${version}-${build}.AppImage";
    hash =
      {
        amd64 = "sha256-ipgIJVwu/EVGanSZZRubkN7nhmTamMYtMxYxixckftc=";
        legacy = "sha256-2XnM+1C9VVB4xcIac5ukGo42gB/BbtMReQx3yAQftQg=";
        rog-ally = "sha256-MdrvlKJneH0mD52Jcvflcz0FmjZgpoONz8c+NCOetNI=";
        steamdeck = "sha256-zCiHJv4tykgOjG1remsTyMI4xFbev7we5TtUsq8mZXQ=";
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
      appName = "org.eden_emu.eden";
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
