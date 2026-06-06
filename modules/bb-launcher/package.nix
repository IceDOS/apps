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
  version = "15.06";

  src = fetchFromGitHub {
    owner = "rainmakerv3";
    repo = "BB_Launcher";
    rev = "Release${version}";
    hash = "sha256-DHosNysqnwHogvwuJ2rp6WxEzD15DyLqSRDc+KI9wmg=";
    fetchSubmodules = true;
  };

  # Upstream Release15.06 leaves `default:` switch cases with only a
  # commented-out `// UNREACHABLE();`, which is an empty label body and a hard
  # error pre-C++23 (this builds as C++20). Both sites are switch defaults, so
  # `break;` is the correct, in-style statement.
  postPatch = ''
    substituteInPlace settings/user_manager.cpp \
      --replace-fail '// UNREACHABLE();' 'break;'
  '';

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
