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
  makeWrapper,
  stdenv,
  steam-run-free,
  wayland,
  zlib,
}:

let
  pname = "simpmusic";
  version = "1.2.1";

  appName = "simpmusic";
  desktopFile = "${appName}.desktop";
  icon = "${appName}.png";

  simpmusicAppimage = fetchurl {
    url = "https://github.com/maxrave-dev/SimpMusic/releases/download/v${version}/SimpMusic-x86_64.AppImage";
    hash = "sha256-mmfFs2NUUHt4ZFdhE+6UmIlLkFX3JeoG3fGjMdO4+8E=";
  };

  desktopItem = makeDesktopItem {
    name = appName;
    desktopName = "SimpMusic";
    comment = "A cross-platform music app using YouTube Music for backend";
    exec = "/@out@/bin/simpmusic %U";
    icon = "/@out@/share/icons/hicolor/256x256/apps/${icon}";
    startupWMClass = "kotlinx-coroutines-c-a\$c";
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
    makeWrapper
  ];

  buildInputs = runtimeLibs;

  appendRunpaths = [
    "${placeholder "out"}/lib/runtime/lib"
    "${placeholder "out"}/lib/runtime/lib/server"
    "${placeholder "out"}/lib/app"
    "${placeholder "out"}/lib/app/resources/vlc"
    "${placeholder "out"}/lib/app/resources/vlc/plugins"
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

  # jpackage's launcher derives its sibling `.cfg`, jar, and resource
  # paths from `realpath(/proc/self/exe)`, so renaming the binary
  # (which `wrapProgram` does) breaks classpath resolution. Instead,
  # leave `bin/SimpMusic` untouched and create a lowercase
  # `bin/simpmusic` wrapper that exports env vars and exec's the
  # launcher under its real name.
  postFixup = ''
    makeWrapper $out/bin/SimpMusic $out/bin/simpmusic \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}"
  '';

  meta = {
    description = "Cross-platform music app using YouTube Music for backend";
    homepage = "https://simpmusic.org/";
    license = lib.licenses.gpl3Only;
    mainProgram = "simpmusic";
    platforms = [ "x86_64-linux" ];
  };
}
