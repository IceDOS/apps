{
  cmake,
  fetchFromGitHub,
  stdenv,
  libX11,
  libXext,
  libXcursor,
  libXrandr,
  libXi,
  libXinerama,
  libXxf86vm,
  wayland,
  wayland-protocols,
  qt6,
}:

stdenv.mkDerivation rec {
  pname = "bb-launcher";
  version = "13.00";

  src = fetchFromGitHub {
    owner = "rainmakerv3";
    repo = "BB_Launcher";
    rev = "Release${version}";
    hash = "sha256-DKvMAk45B6LSVZoR85jpbOq2jT1nsQ0LUwdWAEQ6jwk=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
  ];

  buildInputs =
    let
      inherit (qt6) qtbase qtquick3d qtwebview;
    in
    [
      libX11
      libXcursor
      libXext
      libXi
      libXinerama
      libXrandr
      libXxf86vm
      qtbase
      qtquick3d
      qtwebview
      wayland
      wayland-protocols
    ];
}
