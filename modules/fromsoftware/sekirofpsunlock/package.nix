{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
}:

let
  # Pin refreshed by ./update.sh; `rev` is tracked separately from `version` so an
  # upstream tag-prefix change does not need a package edit.
  source = builtins.fromJSON (builtins.readFile ./source.json);
in
stdenv.mkDerivation {
  pname = "sekirofpsunlock";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "Lahvuun";
    repo = "sekirofpsunlock";
    inherit (source) rev hash;
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
}
