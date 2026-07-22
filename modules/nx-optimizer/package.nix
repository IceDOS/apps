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
  # Pin refreshed by ./update.sh. Each arch's asset URL is recorded rather than rebuilt
  # from `version`: the two differ by an `Arm64.` filename infix that only upstream's
  # naming convention guarantees.
  source = builtins.fromJSON (builtins.readFile ./source.json);

  pname = "nx-optimizer";
  inherit (source) version;

  # Despite the `.AppImage` name, upstream ships a PyInstaller onefile
  # binary (a self-extracting ELF) — there is no squashfs to unpack and
  # `--appimage-extract` is ignored. Install it verbatim and run it under
  # steam-run, which supplies the /lib64 loader the frozen binary needs.
  src = fetchurl { inherit (source.builds.${build}) url hash; };

  icon = "${pname}.png";

  # Onefile binary embeds the icon in its archive; pull the app logo from
  # source for the desktop entry instead.
  iconSrc = fetchurl { inherit (source.icon) url hash; };

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
