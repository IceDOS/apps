{
  SDL2,
  autoPatchelfHook,
  fetchurl,
  ffmpeg,
  kdePackages,
  libusb1,
  libva,
  qt5,
  stdenvNoCC,
  unzip,
}:

stdenvNoCC.mkDerivation (final: {
  pname = "citron";
  version = "0.7.0";

  src = fetchurl {
    url = "https://git.citron-emu.org/api/v4/projects/1/packages/generic/Citron-Canary/${final.version}/citron_linux.zip";
    sha256 = "sha256-Cg18Z9qRL9riiCMKXQPUyQKlJ/lHE1kFsDY0xOpZnGE=";
  };

  runtimeLibs =
    let
      inherit (qt5) qtbase qtmultimedia;
    in
    [
      SDL2
      ffmpeg
      libusb1
      libva
      qtbase
      qtmultimedia
    ];

  nativeBuildInputs =
    let
      inherit (kdePackages) wrapQtAppsHook;
    in
    [
      autoPatchelfHook
      wrapQtAppsHook
    ]
    ++ final.runtimeLibs;

  dontUnpack = true;

  installPhase =
    let
      inherit (final) pname;
    in
    ''
      mkdir -p $out/share/applications
      ${unzip}/bin/unzip $src -d $out

      for f in "$out/bin"/*; do
        chmod +x "$f"
      done

      cat > $out/share/applications/${pname}.desktop <<EOF
      [Desktop Entry]
      Name=Citron
      Exec=${pname}
      Icon=applications-games
      Type=Application
      Categories=Utility;
      Terminal=false
      EOF
    '';
})
