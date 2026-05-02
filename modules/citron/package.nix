{
  build ? "x86_64_v3",
  fetchurl,
  makeDesktopItem,
  stdenvNoCC,
}:

let
  name = pname;
  pname = "citron";
  version = "0.12.25";
  commitHash = "01c042048";

  appName = "org.citron_emu.citron";
  desktopFile = "${appName}.desktop";
  icon = "${appName}.svg";

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

  desktopItem = makeDesktopItem {
    name = appName;
    desktopName = "Citron";
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

    cp ${citronAppimage} $out/lib/citron.AppImage
    chmod +x $out/lib/citron.AppImage
    $out/lib/citron.AppImage --appimage-extract
    rm $out/lib/citron.AppImage
    rm AppDir/lib
    mv AppDir/* $out

    install -Dm644 ${desktopItem}/share/applications/${desktopFile} \
      $out/share/applications/${desktopFile}
    substituteInPlace $out/share/applications/${desktopFile} \
      --replace-fail "/@out@" "$out"

    ln -s $out/${icon} $out/share/applications/${icon}
  '';
}
