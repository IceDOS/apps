{
  fetchFromGitHub,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation rec {
  name = "scopebuddy";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "HikariKnight";
    repo = "ScopeBuddy";
    rev = version;
    hash = "sha256-NhJ1duURHGKJ1L43Hxymgbz3hFioP/jGkkcH/phGqIM=";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -Dm755 bin/$name $out/bin/$name
    runHook postInstall
  '';
}
