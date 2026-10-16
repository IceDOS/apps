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

  # shadnet forces protobuf_FORCE_FETCH_DEPENDENCIES, so protobuf fetches abseil at
  # configure time. Pin it locally for an offline build. nixpkgs' shadps4 pins the same.
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

  # Adds the BloodborneSeamlessAnySummonType key (see config.toml).
  patches = [ ./patches/seamless-any-summon-type.patch ];

  # -F0: no fuzz, so a hunk whose context text changed fails instead of applying wrong.
  patchFlags = [
    "-p1"
    "-F0"
  ];

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qthttpserver
  ];

  postPatch = ''
        # The server chdirs to its executable dir and writes db/shadnet.db there, so
        # it fails to start in the read-only store. Send it to a writable dir.
        substituteInPlace src/main.cpp \
          --replace '#include <QLoggingCategory>' '#include <QLoggingCategory>
    #include <QStandardPaths>' \
          --replace '    // Set working directory to executable location' '    // The Nix store dir is read-only, so write state to a writable dir' \
          --replace '    QDir::setCurrent(QCoreApplication::applicationDirPath());' '    const QString stateHome = qgetenv("SHADNET_HOME").isEmpty()
            ? QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
            : QString::fromLocal8Bit(qgetenv("SHADNET_HOME"));
        QDir().mkpath(stateHome);
        QDir::setCurrent(stateHome);'

    # shadnet-sample registers accounts on a self-hosted server, so ship it too. The
    # root project omits it, and a standalone build would rebuild protobuf.
    printf '\nadd_subdirectory(clientsample)\n' >> CMakeLists.txt # No trailing newline.
    printf 'install(TARGETS shadnet-sample RUNTIME DESTINATION bin)\n' >> CMakeLists.txt
  '';

  cmakeFlags = [
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_ABSL" "${abseilCppSrc}")
  ];

  meta = {
    description = "Self-hosted Bloodborne co-op (shadNet) P2P server for shadPS4";
    homepage = "https://github.com/Wozzardman/shadnet-p2p";
    license = lib.licenses.gpl2Plus;
    mainProgram = "shadnet";
  };
}
