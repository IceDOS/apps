{
  fetchFromGitHub,
  lib,
  makeWrapper,
  python3,
  stdenvNoCC,
}:

let
  # Pin refreshed by ./update.sh. The server ships inside the bbport repo, so it moves
  # with bbport releases and speaks the same relay protocol as that client.
  source = builtins.fromJSON (builtins.readFile ./source.json);
in
stdenvNoCC.mkDerivation {
  pname = "bbsc-gameserver";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "deadinside28";
    repo = "bloodborne_pc";
    inherit (source) rev hash;
  };

  sourceRoot = "source/scripts/bbsc_gameserver";

  nativeBuildInputs = [ makeWrapper ];

  # Logs and data default to the script's own dir, which is read-only in the store.
  # Send them to BBSC_GAMESERVER_HOME, else ~/.local/share/bbsc-gameserver.
  postPatch = ''
    substituteInPlace bbsc_gameserver.py \
      --replace-fail 'HERE = os.path.dirname(os.path.abspath(__file__))' 'HERE = os.path.dirname(os.path.abspath(__file__))
    STATE_HOME = os.environ.get("BBSC_GAMESERVER_HOME") or os.path.join(
        os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "bbsc-gameserver")' \
      --replace-fail 'default=os.path.join(HERE, "logs")' 'default=os.path.join(STATE_HOME, "logs")' \
      --replace-fail 'else HERE' 'else STATE_HOME'
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/bbsc-gameserver $out/share/doc/bbsc-gameserver
    cp bbsc_gameserver.py bbhost_service.py ss_info_template.xml $out/share/bbsc-gameserver/
    cp README.md NOTICE.txt LICENSE.NoDreamForHunter $out/share/doc/bbsc-gameserver/

    # Python would try to write __pycache__ beside the read-only scripts.
    makeWrapper ${lib.getExe python3} $out/bin/bbsc-gameserver \
      --set PYTHONDONTWRITEBYTECODE 1 \
      --add-flags $out/share/bbsc-gameserver/bbsc_gameserver.py

    runHook postInstall
  '';

  meta = {
    description = "BBSC game server for Bloodborne seamless co-op (server list, summons, relays)";
    homepage = "https://github.com/deadinside28/bloodborne_pc";
    license = with lib.licenses; [
      gpl2Plus
      mit
    ];
    mainProgram = "bbsc-gameserver";
    platforms = lib.platforms.linux;
  };
}
