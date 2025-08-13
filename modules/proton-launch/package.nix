{
  fetchFromGitHub,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation rec {
  name = "scopebuddy";
  version = "1.1.2";

  src = fetchFromGitHub {
    owner = "HikariKnight";
    repo = "ScopeBuddy";
    rev = version;
    hash = "sha256-o5fuI7K7wkJAZRQLwnRaGf1GKQkRUd3v18Ai5Qx5XJA=";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -Dm755 bin/$name $out/bin/$name
    runHook postInstall
  '';
}
