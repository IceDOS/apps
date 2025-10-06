{
  fetchurl,
  gnutar,
  libgcc,
  stdenv,
  version,
}:

let
  part1 = fetchurl {
    url = "https://github.com/deiteris/voice-changer/releases/download/${version}/voice-changer-linux-amd64-rocm.tar.gz.aa";
    hash = "sha256-fRHt4hDvdifjWr4sY6Hg6cdphq3WOpagOPpCUU768is=";
  };

  part2 = fetchurl {
    url = "https://github.com/deiteris/voice-changer/releases/download/${version}/voice-changer-linux-amd64-rocm.tar.gz.ab";
    hash = "sha256-hh2YGmsAxBdkBvJ+c9Omfl8C/xzbNuQoQdrfF/4nBDI=";
  };

  part3 = fetchurl {
    url = "https://github.com/deiteris/voice-changer/releases/download/${version}/voice-changer-linux-amd64-rocm.tar.gz.ac";
    hash = "sha256-dcMWU84hqL/1ju6rz8rHUwRqLWi02W6SfECombb0Xf8=";
  };
in
stdenv.mkDerivation {
  name = "rvc-audio-source";
  dontUnpack = true;

  installPhase =
    let
      internalPath = "MMVCServerSIO/_internal";
    in
    ''
      mkdir $out
      cd $out

      (
        cat ${part1}
        cat ${part2}
        cat ${part3}
      ) | ${gnutar}/bin/tar xzf -

      rm ${internalPath}/libstdc++.so.6
      cp ${stdenv.cc.cc.lib}/lib/libstdc++.so* ${internalPath}/

      rm ${internalPath}/libgcc_s.so.1
      cp ${libgcc}/lib/libgcc_s.so* ${internalPath}/

      ln -s torch/lib/rocblas ./${internalPath}/
    '';
}
