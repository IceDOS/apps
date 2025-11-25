{
  fetchurl,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (final: {
  pname = "reigntweak";
  version = "ReleaseP1";

  src = fetchurl {
    url = "https://github.com/Minksh/ReignTweak/releases/download/ReleaseP1/reigntweak.tar.gz";
    sha256 = "sha256-lvwT9XscZ4DTaaMkRlsNiejWKXc6/qshn+KrokhlPdU=";
  };

  unpackPhase = ''
    tar xf $src
  '';

  installPhase =
    let
      inherit (final) pname;
      binPath = "$out/bin";
    in
    ''
      mkdir -p ${binPath}
      mv ${pname} ${binPath}/${pname}
    '';
})
