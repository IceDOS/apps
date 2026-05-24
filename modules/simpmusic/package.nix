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
  pname = "simpmusic";
  version = "1.3.0";

  appName = "simpmusic";
  desktopFile = "${appName}.desktop";
  icon = "${appName}.png";

  simpmusicAppimage = fetchurl {
    url = "https://github.com/maxrave-dev/SimpMusic/releases/download/v${version}/SimpMusic-x86_64.AppImage";
    hash = "sha256-nxVAAjUISxEGzLN6SJ/4c37RBLHgX6AhuQXI9b9A238=";
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
