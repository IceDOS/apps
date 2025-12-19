{
  fetchFromGitHub,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (final: {
  name = "scopebuddy";
  version = "1.3.1";

  src = fetchFromGitHub {
    owner = "HikariKnight";
    repo = "ScopeBuddy";
    tag = final.version;
    hash = "sha256-mTDg36TQd0Q3CsNCfOxM55JhyXYHEcV41NWsiaUB0+4=";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -Dm755 bin/$name $out/bin/$name
    runHook postInstall
  '';
})
