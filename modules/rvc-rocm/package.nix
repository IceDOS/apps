{
  autoPatchelfHook,
  callPackage,
  gfx_version ? "10.3.0",
  libdrm,
  libtorch-bin,
  portaudio,
  stdenvNoCC,
  version ? "b2332",
  zlib,
}:

stdenvNoCC.mkDerivation (
  final:
  let
    binName = final.pname;
    binPath = "$out/bin/${binName}";
    rvc_rocm_dir = "$out/lib/${binName}/";
    server_path = "${rvc_rocm_dir}${binName}";
    src = callPackage ./source.nix { inherit version; };
  in
  {
    inherit version;
    pname = "rvc-rocm";
    dontUnpack = true;

    buildInputs = [
      zlib
    ];

    nativeBuildInputs = [
      autoPatchelfHook
    ];

    installPhase = ''
      mkdir -p $out/bin ${rvc_rocm_dir}
      ln -s ${src}/MMVCServerSIO/_internal ${rvc_rocm_dir}
      cp -r ${src}/MMVCServerSIO/MMVCServerSIO ${server_path}
    '';

    postFixup = ''
      cat << EOF >${binPath}
      #!/usr/bin/env bash
      export LD_LIBRARY_PATH=${src}/MMVCServerSIO/_internal/torch/lib:${libdrm}/lib:${portaudio}/lib:${libtorch-bin}/lib
      export HSA_OVERRIDE_GFX_VERSION=${gfx_version}

      mkdir -p ~/.cache/rvc-rocm
      cd ~/.cache/rvc-rocm

      rm -f _internal
      ln -s ${rvc_rocm_dir}_internal ./
      rm -f ${binName}
      cp ${server_path} ./
      exec ./${binName} "$@"
      EOF

      chmod +x ${binPath}
    '';
  }
)
