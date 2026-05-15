{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "sekirofpsunlock";
  version = "0.2.3";

  src = fetchFromGitHub {
    owner = "Lahvuun";
    repo = "sekirofpsunlock";
    rev = "v${finalAttrs.version}";
    hash = "sha256-tdKm7VNlOQST2uIXTajD7BCbhLktNRysOuDSYd9ONEU=";
  };

  nativeBuildInputs = [
    meson
    ninja
  ];

  postPatch = ''
    substituteInPlace src/main.c \
      --replace-fail '"usage: %s <timeout-seconds> <argument> {<argument>}\n", argv[0]' \
                     '"usage: sekirofpsunlock <timeout-seconds> <argument> {<argument>}\n"'
  '';

  mesonBuildType = "release";

  installPhase = ''
    runHook preInstall
    install -Dm755 sekirofpsunlock $out/bin/sekirofpsunlock
    runHook postInstall
  '';

  meta = {
    description = "Patches Sekiro on Linux to unlock the FPS cap and set custom resolutions";
    homepage = "https://github.com/Lahvuun/sekirofpsunlock";
    license = lib.licenses.mit;
    mainProgram = "sekirofpsunlock";
    platforms = [ "x86_64-linux" ];
  };
})
