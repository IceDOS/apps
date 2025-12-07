{
  fetchFromGitHub,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (final: {
  name = "scopebuddy";
  version = "1.3.0";

  src = fetchFromGitHub {
    owner = "HikariKnight";
    repo = "ScopeBuddy";
    tag = final.version;
    hash = "sha256-tJkIt1io4M9X4Lzs/mm4K5xd7ZUCMnXVCeWv4huccx4=";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -Dm755 bin/$name $out/bin/$name
    runHook postInstall
  '';
})
