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

let
  # Pin refreshed by ./update.sh. Because of `fetchSubmodules`, its hash comes from
  # nix-prefetch-git rather than the release tarball, which carries no submodule content.
  source = builtins.fromJSON (builtins.readFile ./source.json);
in
stdenv.mkDerivation {
  pname = "bb-launcher";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "rainmakerv3";
    repo = "BB_Launcher";
    inherit (source) rev hash;
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
