{
  coreutils,
  fetchFromGitHub,
  findutils,
  gawk,
  gnugrep,
  gnused,
  installShellFiles,
  jq,
  lib,
  libnotify,
  makeWrapper,
  procps,
  psmisc,
  stdenvNoCC,
  util-linux,
}:

let
  # Pin refreshed by ./update.sh; `rev` is tracked separately from `version` so an
  # upstream tag-prefix change does not need a package edit.
  source = builtins.fromJSON (builtins.readFile ./source.json);

  pname = "wl-freeze";
  inherit (source) version;

  runtimeDeps = [
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    jq
    libnotify
    procps
    psmisc
    util-linux
  ];
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  src = fetchFromGitHub {
    owner = "Zerodya";
    repo = "wl-freeze";
    inherit (source) rev hash;
  };

  nativeBuildInputs = [
    makeWrapper
    installShellFiles
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 wl-freeze $out/bin/wl-freeze

    installShellCompletion \
      --cmd wl-freeze \
      --bash completions/bash/wl-freeze \
      --zsh completions/zsh/_wl-freeze \
      --fish completions/fish/wl-freeze.fish

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/wl-freeze \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
  '';

  meta = {
    description = "Utility to suspend a game process (and other programs) in Wayland compositors";
    homepage = "https://github.com/Zerodya/wl-freeze";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "wl-freeze";
  };
}
