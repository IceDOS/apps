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
  version = "unstable-2026-01-13";

  src = fetchFromGitHub {
    owner = "RitzDaCat";
    repo = "scx_cake";
    rev = "213dc994fbdbf0d5da787b296e9bed1d094ad3cb";
    hash = "sha256-ctgx1AWYJ4bV1YMzJGM1w2feM1nHcGjTRrJ+bKLZeZg=";
  };

  RUSTFLAGS = "-C target-cpu=native";

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "scx_cargo-1.0.26" = "sha256-WYVPpwNM3CNRzv25nZ30zmh0HUDG4Ua4vqZrJ8EQ5SM=";
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
