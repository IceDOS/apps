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
  version = "15.07";

  src = fetchFromGitHub {
    owner = "rainmakerv3";
    repo = "BB_Launcher";
    rev = "Release${version}";
    hash = "sha256-0GYB3IcmhTmQ0QctTXRMkaGx9CTA/QBZh54EiF4UiU4=";
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
