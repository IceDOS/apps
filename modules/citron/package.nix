{
  SDL2,
  autoPatchelfHook,
  build ? "native",
  fetchurl,
  ffmpeg,
  kdePackages,
  libusb1,
  libva,
  qt6,
  stdenvNoCC,
  unzip,
}:

stdenvNoCC.mkDerivation (final: {
  pname = "citron";
  version = "0.7.1";

  hash =
    {
      compat = "sha256-L844iTIHhOb0wJZSE5s5MyTXDrjQdJ0KOobPQGap29M=";
      native = "sha256-wLwHrOIhHNeKTicH+Gzr16rZhnibOEFYjNcoFuY0zNs=";
      steamdeck = "sha256-DoJGqw6XKylI87cjWNGX9/51RIxFhWbwHW718edRQvg=";
    }
    .${build};

  src = fetchurl {
    inherit (final) hash;
    url = "https://git.citron-emu.org/api/v4/projects/1/packages/generic/Citron/${final.version}/citron_linux_${build}.zip";
  };

  runtimeLibs =
    let
      inherit (qt6) qtbase qtmultimedia;
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
