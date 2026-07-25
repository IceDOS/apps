{
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  autoPatchelfHook,
  bash,
  cairo,
  cups,
  dbus,
  expat,
  extractAppImage,
  fetchurl,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  installDesktopEntry,
  lib,
  libX11,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libdrm,
  libusb1,
  libxcb,
  libxkbcommon,
  makeDesktopItem,
  mesa,
  nspr,
  nss,
  pango,
  stdenv,
  steam-run-free,
  udev,
}:

let
  source = builtins.fromJSON (builtins.readFile ./source.json);

  pname = "ubports-installer";
  inherit (source) version;

  appName = "ubports-installer";
  desktopFile = "${appName}.desktop";
  icon = "${appName}.png";

  ubportsAppimage = fetchurl {
    inherit (source) url hash;
  };

  desktopItem = makeDesktopItem {
    name = appName;
    desktopName = "UBports Installer";
    comment = "Install Ubuntu Touch on UBports devices";
    exec = "/@out@/bin/${pname} %U";
    icon = "/@out@/share/icons/hicolor/512x512/apps/${icon}";
    startupWMClass = "ubports-installer";
    type = "Application";

    categories = [
      "Utility"
    ];
  };
in
stdenv.mkDerivation {
  inherit pname version;

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libdrm
    libusb1
    libxcb
    libxkbcommon
    mesa
    nspr
    nss
    pango
    udev
  ];

  installPhase = ''
        runHook preInstall

    ${extractAppImage {
      src = ubportsAppimage;
      extractedDir = "squashfs-root";
      steamRun = steam-run-free;
    }}

    # Remove bundled helper libs that autoPatchelf can't satisfy and aren't needed
    rm -f $out/usr/lib/libappindicator.so.1
    rm -f $out/usr/lib/libgconf-2.so.4
    rm -f $out/usr/lib/libindicator.so.7
    rm -f $out/usr/lib/libnotify.so.4
    rm -f $out/usr/lib/libXss.so.1
    rm -f $out/usr/lib/libXtst.so.6

        mkdir -p $out/bin
        cat > $out/bin/${pname} <<WRAPPER
    #!${bash}/bin/bash
    exec $out/${pname}.bin --no-sandbox "\$@"
    WRAPPER
        chmod +x $out/bin/${pname}

        install -Dm644 $out/${icon} \
          $out/share/icons/hicolor/512x512/apps/${icon}

        ${installDesktopEntry { inherit desktopItem desktopFile; }}

        runHook postInstall
  '';

  meta = {
    description = "Install Ubuntu Touch on UBports devices";
    homepage = "https://devices.ubuntu-touch.io";
    license = lib.licenses.gpl3Only;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
  };
}
