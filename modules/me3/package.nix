{
  autoPatchelfHook,
  fetchurl,
  gcc,
  libGL,
  stdenvNoCC,
  steam-run-free,
}:

stdenvNoCC.mkDerivation (final: {
  pname = "me3";
  version = "0.9.0";

  src = fetchurl {
    url = "https://github.com/garyttierney/me3/releases/download/v${final.version}/me3-linux-amd64.tar.gz";
    sha256 = "sha256-2U4fqvmfvQZ3/G6/HpiR1hACmiOjHr+cYs5wxD/49y8=";
  };

  nativeBuildInputs =
    let
      inherit (gcc.cc) lib;
    in
    [
      autoPatchelfHook
      lib
    ];

  sourceRoot = "bin";

  installPhase =
    let
      inherit (final) pname;
      binPath = "$out/bin";
      me3BinPath = "${binPath}/me3-bin";
      me3WrapperPath = "${binPath}/me3";
      windowsBinPath = "$out/share/${pname}/windows-bin";
    in
    ''
      mkdir -p ${binPath} ${windowsBinPath}
      mv ${pname} ${me3BinPath}
      mv win64/* ${windowsBinPath}

      echo "export LD_LIBRARY_PATH=${libGL}/lib; ${steam-run-free}/bin/steam-run ${me3BinPath} \"\$@\"" > ${me3WrapperPath}
      chmod +x ${me3WrapperPath}
    '';
})
