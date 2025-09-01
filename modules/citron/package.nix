{
  build ? "anylinux-x86_64_v3",
  fetchurl,
  stdenvNoCC,
}:

let
  name = pname;
  pname = "citron";
  version = "0.6.1";

  citronAppimage = fetchurl {
    url = "https://github.com/pkgforge-dev/Citron-AppImage/releases/download/v${version}/Citron-v${version}-${build}.AppImage";
    hash =
      {
        anylinux-x86_64 = "sha256-MDrM4n6s0sPVl0d9pIZ2XLKXYw0AX+5znflAwquZ6o0=";
        anylinux-x86_64_v3 = "sha256-Hjh2xbZJe/0OoXgmC1vKkzMfOpW95pMhqhTOP342bqA=";
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
      citronBin = "$out/bin/citron";
      citronLibRun = "$out/lib/AppRun";
      desktopFile = "${appName}.desktop";
      desktopFilePath = "$out/share/applications/${desktopFile}";
      icon = "${appName}.svg";
      iconPath = "$out/share/applications/${icon}";
    in
    ''
      mkdir -p $out/lib $out/bin $out/share/applications

      cp ${citronAppimage} ${appImagePath}
      chmod +x ${appImagePath}
      ${appImagePath} --appimage-extract
      rm ${appImagePath}
      mv AppDir/* $out/lib
      rm -r AppDir squashfs-root

      ln -s $out/lib/${desktopFile} ${desktopFilePath}
      ln -s $out/lib/${icon} ${iconPath}

      substituteInPlace ${desktopFilePath} --replace-fail "${appName}" "${iconPath}" \
        --replace-fail "Name=citron" "Name=Citron"

      ln -s ${citronLibRun} ${citronBin}
      chmod +x ${citronBin}
    '';
}
