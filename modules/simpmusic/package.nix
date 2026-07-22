{
  alsa-lib,
  autoPatchelfHook,
  dbus,
  extractAppImage,
  fetchurl,
  fontconfig,
  freetype,
  glib,
  gtk3,
  installDesktopEntry,
  lib,
  libGL,
  libpulseaudio,
  libx11,
  libxcb,
  libxcursor,
  libxext,
  libxi,
  libxkbcommon,
  libxrender,
  libxtst,
  makeDesktopItem,
  stdenv,
  steam-run-free,
  wayland,
  zlib,
}:

let
  # Pin refreshed by ./update.sh. The AppImage asset name carries no version, so the
  # resolved download URL is recorded rather than rebuilt from `version`.
  source = builtins.fromJSON (builtins.readFile ./source.json);

  pname = "simpmusic";
  inherit (source) version;

  appName = "simpmusic";
  desktopFile = "${appName}.desktop";
  icon = "${appName}.png";

  simpmusicAppimage = fetchurl {
    inherit (source) url hash;
  };

  desktopItem = makeDesktopItem {
    name = appName;
    desktopName = "SimpMusic";
    comment = "A cross-platform music app using YouTube Music for backend";
    exec = "/@out@/bin/simpmusic %U";
    icon = "/@out@/share/icons/hicolor/256x256/apps/${icon}";
    startupWMClass = "com-maxrave-simpmusic-MainKt";
    type = "Application";

    categories = [
      "AudioVideo"
      "Audio"
    ];
  };

  runtimeLibs = [
    alsa-lib
    dbus
    fontconfig
    freetype
    glib
    gtk3
    libGL
    libpulseaudio
    libx11
    libxcb
    libxcursor
    libxext
    libxi
    libxkbcommon
    libxrender
    libxtst
    wayland
    zlib
  ];
in
stdenv.mkDerivation {
  inherit pname version;

  src = simpmusicAppimage;

  dontUnpack = true;

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = runtimeLibs;

  appendRunpaths = [
    "${placeholder "out"}/lib/runtime/lib"
    "${placeholder "out"}/lib/runtime/lib/server"
    "${placeholder "out"}/lib/app"
    "${placeholder "out"}/lib/app/vlc"
    "${placeholder "out"}/lib/app/vlc/plugins"
    "${placeholder "out"}/lib/app/plugins"
  ];

  # The bundled VLC ships every plugin upstream builds (Qt UI, vdpau,
  # mtp, upnp, libsecret keystore, lua, svg, etc.) and references libs
  # we don't ship. SimpMusic only uses the audio decode/output plugins;
  # missing optional plugins fail silently at load time and the app
  # still plays YouTube Music streams.
  autoPatchelfIgnoreMissingDeps = true;

  installPhase = ''
    runHook preInstall

    ${extractAppImage {
      src = simpmusicAppimage;
      extractedDir = "squashfs-root";
      steamRun = steam-run-free;
    }}

    install -Dm644 $out/${icon} \
      $out/share/icons/hicolor/256x256/apps/${icon}

    ${installDesktopEntry { inherit desktopItem desktopFile; }}

    runHook postInstall
  '';

  meta = {
    description = "Cross-platform music app using YouTube Music for backend";
    homepage = "https://simpmusic.org/";
    license = lib.licenses.gpl3Only;
    mainProgram = "simpmusic";
    platforms = [ "x86_64-linux" ];
  };
}
