{
  build ? "x86_64",
  fetchurl,
  installDesktopEntry,
  lib,
  makeDesktopItem,
  makeWrapper,
  steam-run-free,
  stdenvNoCC,
  xclip,
}:

let
  pname = "nx-optimizer";
  version = "3.2.0";

  # x86_64 and Arm64 assets differ only by this filename infix.
  archInfix =
    {
      x86_64 = "";
      aarch64 = "Arm64.";
    }
    .${build};

  # Despite the `.AppImage` name, upstream ships a PyInstaller onefile
  # binary (a self-extracting ELF) — there is no squashfs to unpack and
  # `--appimage-extract` is ignored. Install it verbatim and run it under
  # steam-run, which supplies the /lib64 loader the frozen binary needs.
  src = fetchurl {
    url = "https://github.com/MaxLastBreath/nx-optimizer/releases/download/manager-${version}/NX.Optimizer.${archInfix}${version}.AppImage";

    hash =
      {
        x86_64 = "sha256-a29nCz9KbGFd2vhrMMMUUycKrWqIPCBEO7tFoyaxdNg=";
        aarch64 = "sha256-vPZY84PULlF2EgDE+lXcuj9yWIkI/eUOWMnlc+5Uztc=";
      }
      .${build};
  };

  icon = "${pname}.png";

  # Onefile binary embeds the icon in its archive; pull the app logo from
  # source for the desktop entry instead.
  iconSrc = fetchurl {
    url = "https://raw.githubusercontent.com/MaxLastBreath/nx-optimizer/manager-${version}/src/GUI/LOGO.png";
    hash = "sha256-c8auhId5jWPkcN4KfYFYoYa/bTht7urgfMoDGkxDKxg=";
  };

  desktopFile = "${pname}.desktop";

  desktopItem = makeDesktopItem {
    name = pname;
    desktopName = "NX Optimizer";
    comment = "Nintendo Switch game optimizer and UltraCam mod manager";
    exec = "/@out@/bin/${pname}";
    icon = "/@out@/share/pixmaps/${icon}";
    type = "Application";

    categories = [
      "Game"
    ];
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    install -Dm755 ${src} $out/libexec/${pname}/NX.Optimizer.AppImage

    # PyInstaller onefile: hardcoded /lib64 loader, self-extracts to a
    # tmpdir at runtime. Run it inside steam-run's FHS and expose xclip
    # (clipboard, required per upstream README) on PATH.
    makeWrapper ${steam-run-free}/bin/steam-run $out/bin/${pname} \
      --add-flags $out/libexec/${pname}/NX.Optimizer.AppImage \
      --prefix PATH : ${lib.makeBinPath [ xclip ]}

    install -Dm644 ${iconSrc} $out/share/pixmaps/${icon}

    ${installDesktopEntry { inherit desktopItem desktopFile; }}
  '';
}
