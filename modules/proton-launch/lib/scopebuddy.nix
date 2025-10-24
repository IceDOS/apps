{
  fetchFromGitHub,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (final: {
  name = "scopebuddy";
  version = "1.2.2";

  src = fetchFromGitHub {
    owner = "HikariKnight";
    repo = "ScopeBuddy";
    tag = final.version;
    hash = "sha256-7cyEh/8TGuj6AUXe0qNcF6J4QH0ZZyzRed0EV5QZAU0=";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -Dm755 bin/$name $out/bin/$name
    runHook postInstall
  '';
})
