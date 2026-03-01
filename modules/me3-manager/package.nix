{
  autoPatchelfHook,
  fetchurl,
  lib,
  libGL,
  libxcb,
  libz,
  me3,
  stdenvNoCC,
  steam-run-free,
  wayland,
}:

stdenvNoCC.mkDerivation (
  final:
  let
    version = "1.4.3";

    me3Manager = fetchurl {
      url = "https://github.com/2Pz/me3-manager/releases/download/${version}/Me3_Manager_1.4.3_Linux.AppImage";
      sha256 = "sha256-fnV1rqEfZhlbnndms1Fw0tH1WHd6qa6s8dMj8tEiVxg=";
    };
  in
  {
    inherit version;
    pname = "me3-manager";

    nativeBuildInputs = [
      autoPatchelfHook
      libz
    ];

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/lib

      cp ${me3Manager} $out/appimage
      chmod +x $out/appimage
      $out/appimage --appimage-extract

      mv squashfs-root/usr/* $out
      mv $out/bin/me3-manager $out/bin/.me3-manager-unwrapped
      ln -s ${me3}/bin/me3-unwrapped $out/lib/me3

      echo "
        PATH="$out/lib"

        LD_LIBRARY_PATH="${
          lib.makeLibraryPath [
            libGL
            libxcb
            wayland
          ]
        }"

        ${steam-run-free}/bin/steam-run $out/bin/.me3-manager-unwrapped
      " > $out/bin/me3-manager

      chmod +x $out/bin/me3-manager
    '';
  }
)
