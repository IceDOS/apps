{
  lib,
  stdenv,
  fetchFromGitHub,
  autoPatchelfHook,
  buildGoModule,
  buildNpmPackage,
  cmake,
  pkg-config,
  python3,
  wayland-scanner,
  # backend
  avahi,
  boost,
  curl,
  libcap,
  libdrm,
  libevdev,
  libgbm,
  libnotify,
  libopus,
  libpulseaudio,
  libva,
  libvdpau,
  miniupnpc,
  nlohmann_json,
  numactl,
  openssl,
  amf-headers,
  svt-av1,
  # x11 / wayland
  libx11,
  libxcb,
  libxfixes,
  libxi,
  libxrandr,
  libxtst,
  libxdmcp,
  libxkbcommon,
  libepoxy,
  wayland,
  # transitive (kept explicit so autoPatchelfHook resolves the vendored ffmpeg)
  libffi,
  pcre,
  pcre2,
  libuuid,
  libselinux,
  libsepol,
  libthai,
  libdatrie,
  libappindicator,
  libglvnd,
  # build toggles (set by the IceDOS module overlay)
  go,
  cudaSupport ? false,
  enableBrowserStream ? false,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "polaris";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "papi-ux";
    repo = "polaris";
    tag = "v${finalAttrs.version}";
    hash = "sha256-adX3HfahM8X3uRRX9nu1qypj99xF4gu5Vvd/WksJ/lI=";
    fetchSubmodules = true;
  };

  # Web UI (Vue3/Vite) is built separately so the in-tree CMake target does not
  # need network access. Polaris commits its own package-lock.json.
  ui = buildNpmPackage {
    inherit (finalAttrs) src version;
    pname = "polaris-ui";
    npmDepsHash = "sha256-afvTa7jPdAaa1iic0isdEtBL+Vq06noWgaownMd5jJE=";

    # `npm run build` -> vite -> build/assets/web (see vite.config.js defaults)
    installPhase = ''
      runHook preInstall

      cp -r build/assets/web "$out"

      runHook postInstall
    '';
  };

  # WebTransport helper (Go) built separately so the in-tree CMake target does
  # not need network access or a writable $HOME for the Go build cache.
  browserStreamHelper = buildGoModule {
    inherit (finalAttrs) src version;
    pname = "polaris-browser-stream-helper";
    modRoot = "browser_stream_helper";
    vendorHash = "sha256-+a9Ueh50nmqor7Alr3HeDMc/2wMlNG7DqfA0QVEW4G8=";
    subPackages = [ "." ];
  };

  postPatch = ''
    # Web UI is prebuilt; neuter the in-build npm invocation so the web-ui
    # custom target succeeds without npm/network.
    substituteInPlace cmake/targets/common.cmake \
      --replace-fail 'find_program(NPM npm REQUIRED)' 'set(NPM "true")'

    # Don't install the upstream systemd unit; the IceDOS module ships its own.
    substituteInPlace cmake/packaging/linux.cmake \
      --replace-fail 'find_package(Systemd)' ""
  ''
  + lib.optionalString enableBrowserStream ''
    substituteInPlace cmake/targets/common.cmake \
      --replace-fail \
        'COMMAND "''${GO_EXECUTABLE}" build -trimpath -o "''${BROWSER_STREAM_HELPER_OUTPUT}" .' \
        'COMMAND "''${CMAKE_COMMAND}" -E copy "${finalAttrs.browserStreamHelper}/bin/browser_stream_helper" "''${BROWSER_STREAM_HELPER_OUTPUT}"'
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    python3
    wayland-scanner
    # the vendored (build-deps submodule) ffmpeg libs are prebuilt ELF
    autoPatchelfHook
  ]
  ++ lib.optionals enableBrowserStream [ go ];

  buildInputs = [
    amf-headers
    avahi
    boost
    curl
    libappindicator
    libcap
    libdatrie
    libdrm
    libepoxy
    libevdev
    libffi
    libgbm
    libnotify
    libopus
    libpulseaudio
    libselinux
    libsepol
    libthai
    libuuid
    libva
    libvdpau
    libx11
    libxcb
    libxdmcp
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxtst
    miniupnpc
    nlohmann_json
    numactl
    openssl
    pcre
    pcre2
    svt-av1
    wayland
  ];

  runtimeDependencies = [
    avahi
    libgbm
    libglvnd
    libxcb
    libxrandr
  ];

  cmakeFlags = [
    "-Wno-dev"
    (lib.cmakeBool "BOOST_USE_STATIC" false)
    (lib.cmakeBool "BUILD_DOCS" false)
    (lib.cmakeBool "BUILD_TESTS" false)
    (lib.cmakeBool "POLARIS_ENABLE_NATIVE_ARCH" false)
    (lib.cmakeBool "POLARIS_ENABLE_BROWSER_STREAM" enableBrowserStream)
    # Use the bundled third-party/build-deps ffmpeg instead of a build-time
    # GitHub download (which would fail in the Nix sandbox).
    (lib.cmakeBool "POLARIS_DOWNLOAD_PREPARED_FFMPEG" false)
    (lib.cmakeFeature "POLARIS_PUBLISHER_NAME" "IceDOS")
    (lib.cmakeFeature "POLARIS_PUBLISHER_WEBSITE" "https://github.com/icedos")
    (lib.cmakeFeature "POLARIS_PUBLISHER_ISSUE_URL" "https://github.com/papi-ux/polaris/issues")
  ]
  ++ lib.optionals (!cudaSupport) [
    (lib.cmakeBool "POLARIS_ENABLE_CUDA" false)
    (lib.cmakeBool "CUDA_FAIL_ON_MISSING" false)
  ];

  env = {
    # build_version.cmake reads these to set the version without a .git dir
    BUILD_VERSION = finalAttrs.version;
    BRANCH = "master";
    COMMIT = "";
  };

  # Place the prebuilt web UI where the (now no-op) web-ui target would have,
  # i.e. CMAKE_BINARY_DIR/assets/web. node_modules must exist for the neutered
  # npm-install stamp touch to succeed.
  preBuild = ''
    mkdir -p assets/web
    cp -r ${finalAttrs.ui}/. assets/web/
    mkdir -p ../node_modules
  '';

  buildFlags = [ "polaris" ];

  installPhase = ''
    runHook preInstall

    cmake --install .

    runHook postInstall
  '';

  meta.mainProgram = "polaris";
})
