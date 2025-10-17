{
  atk,
  autoPatchelfHook,
  cairo,
  callPackage,
  dpkg,
  fetchurl,
  fontconfig,
  gcc,
  gdk-pixbuf,
  glib,
  gtk3,
  harfbuzz,
  jdk,
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
    version = "1.12.1";
    versionPrefix = "26";

    src = fetchurl {
      url =
        let
          version = final.version;
          versionPrefix = final.versionPrefix;
        in
        "https://github.com/anandnet/Harmony-Music/releases/download/v${version}/harmonymusic-${version}+${versionPrefix}-linux.deb";

      hash = "sha256-gy96qRXlXdL2iuHxEGR2RBFnRYA5z3yvZhLxIPhAVhk=";
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
        pango
      ];

    nativeBuildInputs = [
      autoPatchelfHook
      dpkg
    ];

    installPhase = ''
      mkdir -p ${binDir}
      mv usr/* $out
      ln -s ${harmonyMusicDir}/lib $out
    '';

    postFixup = ''
      addAutoPatchelfSearchPath ${jdk}/lib/openjdk/lib/server

      substituteInPlace ${shareDir}/applications/harmonymusic.desktop \
        --replace-fail "harmonymusic %U" "${harmonyMusicWrapper}"

      echo "
        export LD_LIBRARY_PATH=${mpv}/lib
        export PATH=$PATH:${xdg-user-dirs}/bin
        exec ${harmonyMusicBin} $@
      " > ${harmonyMusicWrapper}

      chmod +x ${harmonyMusicWrapper}
    '';
  }
)
