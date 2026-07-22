{
  coreutils,
  fetchFromGitHub,
  findutils,
  gnugrep,
  gnused,
  installDesktopEntry,
  kdePackages,
  lib,
  makeDesktopItem,
  makeWrapper,
  stdenvNoCC,
  zenity,
}:

let
  # Pin refreshed by ./update.sh; `rev` is tracked separately from `version` so an
  # upstream tag-prefix change does not need a package edit.
  source = builtins.fromJSON (builtins.readFile ./source.json);

  pname = "unshade";
  inherit (source) version;

  runtimeDeps = [
    coreutils
    findutils
    gnugrep
    gnused
    kdePackages.kdialog
    zenity
  ];

  desktopFile = "unshade.desktop";

  desktopItem = makeDesktopItem {
    name = "unshade";
    desktopName = "UnShade";
    comment = "Clear Linux gaming shader caches";
    exec = "/@out@/bin/unshade";
    icon = "/@out@/share/icons/hicolor/scalable/apps/unshade.svg";
    type = "Application";

    categories = [
      "Game"
      "Utility"
    ];
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  src = fetchFromGitHub {
    owner = "andy10115";
    repo = "UnShade";
    inherit (source) rev hash;
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  # Inject a headless shim: `unshade --all` bypasses zenity/kdialog so the
  # script can run from `icedos gc` / nh-clean without a desktop session.
  # Missing-Steam falls through quietly (exit 0) to keep automated gc green.
  postPatch = ''
    substituteInPlace unshade.sh --replace-fail 'set -e' ${lib.escapeShellArg ''
      set -e

      if [[ "''${1-}" == "--all" ]]; then
        kdialog() {
          case "$1" in
            --error)   shift; printf 'unshade: %b\n' "$1" >&2; exit 0 ;;
            --yesno)   return 0 ;;
            --msgbox)  shift; printf '%b\n' "$1"; return 0 ;;
          esac
        }
        zenity() {
          echo "mesa steam dxvk vkd3d gl"
          return 0
        }
      fi
    ''}
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 unshade.sh $out/bin/unshade
    install -Dm644 UnShade.svg $out/share/icons/hicolor/scalable/apps/unshade.svg

    patchShebangs $out/bin/unshade

    wrapProgram $out/bin/unshade \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}

    ${installDesktopEntry { inherit desktopItem desktopFile; }}

    runHook postInstall
  '';

  meta = {
    description = "Clear Linux gaming shader caches";
    homepage = "https://github.com/andy10115/UnShade";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "unshade";
  };
}
