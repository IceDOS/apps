{
  lib,
  clangStdenv,
  cmake,
  fetchFromGitHub,
  qt6,
}:

let
  # Pin refreshed by ./update.sh. Because of `fetchSubmodules`, its hash comes from
  # nix-prefetch-git rather than the release tarball, which carries no submodule content.
  source = builtins.fromJSON (builtins.readFile ./source.json);

  # shadnet's externals hard-forces protobuf_FORCE_FETCH_DEPENDENCIES, so protobuf
  # FetchContent's abseil at configure time. Feed it a pinned local source so the
  # Nix build stays offline; same pin/hash nixpkgs shadps4 uses.
  abseilCppSrc = fetchFromGitHub {
    owner = "abseil";
    repo = "abseil-cpp";
    tag = "20250512.1";
    hash = "sha256-eB7OqTO9Vwts9nYQ/Mdq0Ds4T1KgmmpYdzU09VPWOhk=";
  };
in
clangStdenv.mkDerivation {
  pname = "shadnet-p2p";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "Wozzardman";
    repo = "shadnet-p2p";
    inherit (source) rev hash;
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qthttpserver
  ];

  # The server chdirs to its own executable dir and writes db/cfg there; in the
  # read-only Nix store that crashes at DB init. Route it to a writable dir,
  # overridable via SHADNET_HOME (which the NixOS service sets).
  postPatch = ''
    substituteInPlace src/main.cpp \
      --replace '#include <QLoggingCategory>' '#include <QLoggingCategory>
#include <QStandardPaths>' \
      --replace '    // Set working directory to executable location' '    // The Nix store dir is read-only, so write state to a writable dir' \
      --replace '    QDir::setCurrent(QCoreApplication::applicationDirPath());' '    const QString stateHome = qgetenv("SHADNET_HOME").isEmpty()
        ? QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
        : QString::fromLocal8Bit(qgetenv("SHADNET_HOME"));
    QDir().mkpath(stateHome);
    QDir::setCurrent(stateHome);'
  '';

  cmakeFlags = [
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_ABSL" "${abseilCppSrc}")
  ];

  # Also build and ship the clientsample CLI (shadnet-sample): it is the only
  # supported way to register accounts on a self-hosted server (open or keyed
  # registration), so server owners need it on the machine that runs shadnet.
  postInstall = ''
    # The cmake configure hook leaves us inside build/, so use the absolute
    # source root (fetchFromGitHub always unpacks to $NIX_BUILD_TOP/source).
    cmake -S "$NIX_BUILD_TOP/source/clientsample" \
      -B "$NIX_BUILD_TOP/source/sample-build" -DCMAKE_BUILD_TYPE=Release \
      -DFETCHCONTENT_SOURCE_DIR_ABSL="${abseilCppSrc}"
    cmake --build "$NIX_BUILD_TOP/source/sample-build" -j "$NIX_BUILD_CORES"
    install -Dm755 "$NIX_BUILD_TOP/source/sample-build/shadnet-sample" \
      "$out/bin/shadnet-sample"
  '';

  meta = {
    description = "Self-hosted Bloodborne co-op (shadNet) P2P server for shadPS4";
    homepage = "https://github.com/Wozzardman/shadnet-p2p";
    license = lib.licenses.gpl2Plus;
    mainProgram = "shadnet";
  };
}
