{
  autoPatchelfHook,
  fetchurl,
  gcc,
  libGL,
  openssl_3,
  stdenvNoCC,
  steam-run-free,
}:

stdenvNoCC.mkDerivation (final: {
  pname = "me3";
  version = "0.10.1";

  src = fetchurl {
    url = "https://github.com/garyttierney/me3/releases/download/v${final.version}/me3-linux-amd64.tar.gz";
    sha256 = "sha256-VhTuk0SxuAKrGEQlxewhlFP1znuJrj52zYo3VoTFAH0=";
  };

  nativeBuildInputs =
    let
      inherit (gcc.cc) lib;
    in
    [
      autoPatchelfHook
      lib
      openssl_3
    ];

  sourceRoot = "bin";

  installPhase =
    let
      inherit (final) pname;
      binPath = "$out/bin";
      me3Unwrapped = "${binPath}/me3-unwrapped";
      me3WrapperPath = "${binPath}/me3";
      windowsBinPath = "$out/share/${pname}/win64";
    in
    ''
      mkdir -p ${binPath} ${windowsBinPath}

      mv ${pname} ${me3Unwrapped}
      chmod +x ${me3Unwrapped}

      mv win64/* ${windowsBinPath}

      echo "export LD_LIBRARY_PATH=${libGL}/lib; ${steam-run-free}/bin/steam-run ${me3Unwrapped} \"\$@\"" > ${me3WrapperPath}
      chmod +x ${me3WrapperPath}
    '';
})
