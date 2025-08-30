{
  appimageTools,
  fetchFromGitHub,
  fetchurl,
  lib,
  makeDesktopItem,
  stdenvNoCC,
}:

let
  name = pname;
  pname = "winboat";
  version = "0.6.3";

  icon = "${
    fetchFromGitHub {
      owner = "TibixDev";
      repo = "winboat";
      tag = "v${version}";
      hash = "sha256-zw71B4xsmaOhVaAHuvmB1Kg0ehperrZedOnt030wdaM=";
    }
  }/icons/icon.png";

  winboat = appimageTools.wrapType2 {
    inherit pname version;
    src = fetchurl {
      url = "https://github.com/TibixDev/winboat/releases/download/v${version}/winboat-${version}.AppImage";
      hash = "sha256-VX/Xf1sX5uf+r+FzXlJdHfCwAK1xyMW1F/SHpV882Jc=";
    };
  };

  desktopItem =
    let
      capitalize =
        string:
        let
          firstChar = builtins.substring 0 1 string;
          remainingChars = builtins.substring 1 (builtins.stringLength string - 1) string;
        in
        lib.toUpper firstChar + remainingChars;
    in
    makeDesktopItem {
      inherit name;

      categories = [ "Utility" ];
      comment = "Run Windows apps on 🐧 Linux with ✨ seamless integration";
      desktopName = capitalize name;
      exec = "${winboat}/bin/winboat";
      icon = "${icon}";
    };
in
stdenvNoCC.mkDerivation rec {
  name = pname;
  src = winboat;

  installPhase = ''
    mkdir $out
    cp -r ${src}/bin $out
    cp -r ${desktopItem}/share $out
  '';
}
