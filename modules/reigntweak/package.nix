{
  fetchurl,
  stdenvNoCC,
}:

let
  # Pin refreshed by ./update.sh, which resolves the release asset by name rather than
  # constructing its URL: upstream shipped `reigntweak.tar.gz` up to ReleaseP1 and a bare
  # `reigntweak` ELF from Release1.2 on, so the URL is recorded instead of derived.
  source = builtins.fromJSON (builtins.readFile ./source.json);
in
stdenvNoCC.mkDerivation {
  pname = "reigntweak";
  inherit (source) version;

  src = fetchurl {
    inherit (source) url hash;
  };

  # The asset is the executable itself, not an archive.
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/reigntweak
    runHook postInstall
  '';
}
