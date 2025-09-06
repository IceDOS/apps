{
  atk,
  cairo,
  callPackage,
  dpkg,
  fetchurl,
  fontconfig,
  gcc,
  gdk-pixbuf,
  glib,
  glibc,
  gtk3,
  harfbuzz,
  lib,
  libayatana-appindicator,
  libayatana-indicator,
  libdbusmenu,
  libepoxy,
  mpv,
  pango,
  stdenvNoCC,
  xdg-user-dirs,
}:

stdenvNoCC.mkDerivation (
  final:
  let
    binDir = "$out/bin";
    shareDir = "$out/share";
    harmonyMusicDir = "${shareDir}/harmonymusic";
    harmonyMusicBin = "${harmonyMusicDir}/harmonymusic";
    harmonyMusicWrapper = "$out/bin/harmony-music";
  in
  {
    pname = "harmony-music";
    version = "1.12.0";

    src = fetchurl {
      url =
        let
          version = final.version;
        in
        "https://github.com/anandnet/Harmony-Music/releases/download/v${version}/harmonymusic-${version}+25-linux.deb";
      hash = "sha256-uEOZ2p3orBTjYkamNNP6WeXz2FSFOkbWtcxEEMcAiD0=";
    };

    buildInputs =
      let
        inherit (gcc) cc;
      in
      [
        (callPackage ./lib/libayatana-ido.nix { })
        atk
        cairo
        cc
        fontconfig
        gdk-pixbuf
        glib
        gtk3
        harfbuzz
        libayatana-appindicator
        libayatana-indicator
        libdbusmenu
        libepoxy
        mpv
        pango
      ];

    nativeBuildInputs = [ dpkg ];

    installPhase = ''
      mkdir -p ${binDir}
      mv usr/* $out
      ln -s ${harmonyMusicDir}/lib $out
    '';

    postFixup = ''
      base="${lib.makeLibraryPath final.buildInputs}"

      patchelf \
        --set-interpreter ${glibc}/lib/ld-linux-x86-64.so.2 \
        ${harmonyMusicBin}

        substituteInPlace ${shareDir}/applications/harmonymusic.desktop \
          --replace-fail "harmonymusic %U" "${harmonyMusicWrapper}"

      (
        echo "
          #!/usr/bin/env bash

          export LD_LIBRARY_PATH=$base:$out/lib
          export PATH=\$PATH:${xdg-user-dirs}/bin
          exec ${harmonyMusicBin} $@
        " > ${harmonyMusicWrapper}

        chmod +x ${harmonyMusicWrapper}
      )
    '';
  }
)
