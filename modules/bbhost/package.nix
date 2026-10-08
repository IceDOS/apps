{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  patchelf,
  makeDesktopItem,
  installDesktopEntry,
  alsa-lib,
  curl,
  dbus,
  icoutils,
  libdecor,
  libdrm,
  libpulseaudio,
  libxkbcommon,
  mesa,
  pipewire,
  udev,
  vulkan-loader,
  wayland,
  libX11,
  libXcursor,
  libXext,
  libXfixes,
  libXi,
  libXrandr,
  libXScrnSaver,
  libXtst,
  zlib,
}:

let
  # Pin refreshed by ./update.sh: the release tag, the Linux tarball's URL and its
  # hash. The URL comes from the release API, so an upstream asset rename cannot
  # turn into a silently broken constructed link.
  source = builtins.fromJSON (builtins.readFile ./source.json);

  # The binary's DT_NEEDED is small (z, curl, Vulkan, libstdc++); SDL3 is built
  # in and dlopens every window, audio and display backend, so it never reaches
  # DT_NEEDED. Everything is supplied via the wrapper's LD_LIBRARY_PATH: leave a
  # backend out and the log says "SDL audio unavailable: Failed loading
  # libasound.so.2" and the mixer runs with no output.
  runtimeLibs = [
    alsa-lib
    dbus
    libdecor
    libdrm
    libpulseaudio
    libxkbcommon
    mesa
    pipewire
    wayland
    libX11
    libXcursor
    libXext
    libXfixes
    libXi
    libXrandr
    libXScrnSaver
    libXtst
  ];

  iconSrc = fetchurl {
    inherit (source.icon) url hash;
  };

  desktopItem = makeDesktopItem {
    name = "bbhost";
    desktopName = "Bloodborne";
    comment = "Run Bloodborne on Windows and Linux";
    exec = "/@out@/bin/bbhost";
    icon = "bbhost";
    terminal = false;
    type = "Application";
    categories = [ "Game" ];
  };
in
stdenv.mkDerivation {
  pname = "bbhost";
  inherit (source) version;

  src = fetchurl {
    inherit (source) url hash;
  };

  nativeBuildInputs = [
    icoutils
    makeWrapper
    patchelf
  ];

  # No auto-patchelf: the shipped binary uses any() dlopen forms that crash the
  # nixpkgs patchelf hook, and the optional Steam overlay dlopens libsteam_api.so
  # which the release doesn't ship. The wrapper below resolves everything.
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # unpackPhase cd'd into the single top-level dir, so cwd is the release root.
    # bbhost resolves plugins/ and patches/ beside its own binary, so the release
    # tree stays intact under libexec.
    mkdir -p $out/libexec/bbhost $out/bin $out/share/doc/bbhost
    cp -a bbhost $out/libexec/bbhost/
    cp -a plugins patches $out/libexec/bbhost/
    cp -a README-linux.txt LICENSE bbhost.example.toml $out/share/doc/bbhost/

    icotool -x ${iconSrc}
    for f in *_*.png; do
      dims=$(echo "$f" | sed -E 's/.*_([0-9]+x[0-9]+)x.*/\1/')
      install -Dm644 "$f" "$out/share/icons/hicolor/$dims/apps/bbhost.png"
    done
    install -Dm644 *_256x256x*.png $out/share/pixmaps/bbhost.png

    ${installDesktopEntry {
      inherit desktopItem;
      desktopFile = "bbhost.desktop";
    }}

    runHook postInstall
  '';

  postFixup = ''
    # The upstream binary asks for /lib64/ld-linux-x86-64.so.2, which NixOS does
    # not provide; point it at the build's dynamic linker before wrapping.
    patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/libexec/bbhost/bbhost

    makeWrapper $out/libexec/bbhost/bbhost $out/bin/bbhost \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath (
          runtimeLibs
          ++ [
            curl
            stdenv.cc.cc.lib
            udev
            vulkan-loader
            zlib
          ]
        )
      }
  '';

  meta = with lib; {
    description = "Host implementation to run Bloodborne on Linux";
    homepage = "https://github.com/droogie/bbhost";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "bbhost";
  };
}
