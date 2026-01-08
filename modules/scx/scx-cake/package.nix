{
  elfutils,
  fetchFromGitHub,
  lib,
  llvmPackages,
  pkg-config,
  rustPlatform,
  zlib,
  zstd,
}:

rustPlatform.buildRustPackage rec {
  pname = "scx-cake";
  version = "unstable-2025-12-27";

  src = fetchFromGitHub {
    owner = "RitzDaCat";
    repo = "scx_cake";
    rev = "e9a4938a385c4bee6d3b352af292c351acc983e2";
    hash = "sha256-WvdGTN2/Vs2v7VWlO3s60DdS2SCkf9do4nzIC5M4XXg=";
  };

  RUSTFLAGS="-C target-cpu=native";

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "scx_cargo-1.0.26" = "sha256-28UegaoknG5AJZ/n8huYTvkQDuKWi9sMvNQ5peWaoQE=";
    };
  };

  postPatch = ''
    ln -s ${./Cargo.lock} Cargo.lock
  '';

  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    elfutils
    zlib
    zstd
  ];

  env = {
    BPF_CLANG = lib.getExe llvmPackages.clang;

    RUSTFLAGS = lib.concatStringsSep " " [
      "-C relocation-model=pic"
      "-C link-args=-lelf"
      "-C link-args=-lz"
      "-C link-args=-lzstd"
    ];
  };

  hardeningDisable = [
    "zerocallusedregs"
  ];
}
