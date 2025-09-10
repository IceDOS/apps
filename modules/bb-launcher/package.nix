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
  version = "9.01";

  src = fetchFromGitHub {
    owner = "rainmakerv3";
    repo = "BB_Launcher";
    rev = "Release${version}";
    hash = "sha256-tcOCq/dq6KQV59ZUsD0aWwSFqjJyuv9+Fi3TDXuD6Nk=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    libX11
    libXext
    libXcursor
    libXrandr
    libXi
    libXinerama
    libXxf86vm
    wayland
    wayland-protocols
    qt6.qtbase
  ];
}
