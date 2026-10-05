{
  stdenv,
  llvmPackages,
  lib,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  qt6,
  glslang,
  vulkan-headers,
  libx11,
  libxext,
  libxcursor,
  libxfixes,
  libxi,
  libxrandr,
  libxscrnsaver,
  libxtst,
  libxkbcommon,
  libpulseaudio,
  alsa-lib,
  dbus,
  libGL,
  wayland,
  wayland-protocols,
  git,
  python3,
  unzip,
  fetchurl,
  installDesktopEntry,
  makeDesktopItem,
  udev,
  vulkan-loader,
}:

let
  source = builtins.fromJSON (builtins.readFile ./source.json);
  opusSrc = fetchFromGitHub {
    owner = "xiph";
    repo = "opus";
    rev = "ddbe48383984d56acd9e1ab6a090c54ca6b735a6";
    hash = "sha256-M1G7ypcfs7nJmXgkyoG96jT/CkgN5BOzy+DGO4LVCvA=";
  };
  xbyakSrc = fetchFromGitHub {
    owner = "herumi";
    repo = "xbyak";
    rev = "44a72f369268f7d552650891b296693e91db86bb";
    hash = "sha256-S4arAwbhTGsUhDFfy5fTGyDvCm0/x/LKiiPTAuRM8Yk=";
  };
  zydisSrc = fetchFromGitHub {
    owner = "zyantific";
    repo = "zydis";
    rev = "120e0e705f8e3b507dc49377ac2879979f0d545c";
    hash = "sha256-5xpebm6cxOlElCKEasfMgyPB4UcbY3kgQvjcogRKR38=";
  };
  zstdSrc = fetchFromGitHub {
    owner = "facebook";
    repo = "zstd";
    rev = "f8745da6ff1ad1e7bab384bd1f9d742439278e99";
    hash = "sha256-tNFWIT9ydfozB8dWcmTMuZLCQmQudTFJIkSr0aG7S44=";
  };
  zarchiveSrc = fetchFromGitHub {
    owner = "Exzap";
    repo = "ZArchive";
    rev = "d2c717730092c7bf8cbb033b12fd4001b7c4d932";
    hash = "sha256-hX637O/mVLTzmG0a9swJu9w+3o26VHo+K/9RhMuf1lI=";
  };
  zycoreSrc = fetchFromGitHub {
    owner = "zyantific";
    repo = "zycore-c";
    rev = "75a36c45ae1ad382b0f4e0ede0af84c11ee69928";
    hash = "sha256-sUCn4yoUuD2gGtnd7nDi/tQFwdY8BdUKY9hFFtHaYJw=";
  };
  # 3rdparty/ffmpeg-core downloads a prebuilt FFmpeg at configure time; the Nix
  # sandbox has no network. ext-ffmpeg-core rev is the ffmpeg-core submodule of src.
  ffmpegPrebuilt = stdenv.mkDerivation {
    pname = "kytyps5-ffmpeg-prebuilt";
    version = source.ffmpegRev;
    src = fetchurl {
      url = "https://github.com/KytyPS5/ext-ffmpeg-core/releases/download/${source.ffmpegRev}/ffmpeg-linux-x64.zip";
      hash = source.ffmpegHash;
    };
    dontUnpack = true;
    nativeBuildInputs = [ unzip ];
    installPhase = ''
      runHook preInstall
      unzip -q $src -d $out
      runHook postInstall
    '';
  };
  desktopFile = "kytyps5.desktop";

  desktopItem = makeDesktopItem {
    name = "kytyps5";
    desktopName = "KytyPS5";
    comment = "PlayStation 5 emulator";
    exec = "/@out@/bin/kyty-launcher";
    icon = "input-gamepad";
    terminal = false;
    type = "Application";
    categories = [ "Game" ];
  };
in
# Mirrors upstream Linux CI (.github/workflows/build.yml): clang, lld, IPO, Release.
llvmPackages.stdenv.mkDerivation {
  pname = "kytyps5";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "KytyPS5";
    repo = "KytyPS5";
    inherit (source) rev hash;
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    cmake
    ninja
    # Wrapped ld.lld, so the Nix linker wrapper adds store RUNPATHs (Qt, libstdc++).
    llvmPackages.bintools
    # CMake IPO with clang needs llvm-ar and llvm-ranlib.
    llvmPackages.llvm
    pkg-config
    glslang
    qt6.wrapQtAppsHook
    git
    python3
    vulkan-loader
  ];

  # The launcher writes kyty_run.sh and _Patches/ next to the emulator binary and
  # runs the emulator from there; the store is read-only, so the patch moves both
  # to the user config dir (~/.config/kyty-launcher).
  patches = [ ./patches/0001-write-generated-files-to-user-config-dir.patch ];

  # The source has no .git, so upstream's `git rev-parse` yields "unknown" and the
  # emulator disables its Vulkan pipeline cache. Pin the revision instead.
  postPatch = ''
    cat > src/generate_version.cmake <<'EOF'
    set(KYTY_GIT_VERSION "${source.rev}")
    set(KYTY_GIT_HASH "${builtins.substring 0 7 source.commit}")
    set(KYTY_GIT_REVISION "${source.commit}")
    configure_file("''${INPUT_FILE}" "''${OUTPUT_FILE}")
    EOF
  '';

  buildInputs = [
    qt6.qtbase
    qt6.qtsvg
    qt6.qttools
    qt6.qtwayland
    qt6.qttranslations
    vulkan-headers
    libx11
    libxext
    libxcursor
    libxfixes
    libxi
    libxrandr
    libxscrnsaver
    libxtst
    libxkbcommon
    libpulseaudio
    alsa-lib
    dbus
    libGL
    udev
    wayland
    wayland-protocols
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON"
    "-DFETCHCONTENT_SOURCE_DIR_OPUS=${opusSrc}"
    "-DFETCHCONTENT_SOURCE_DIR_XBYAK=${xbyakSrc}"
    "-DFETCHCONTENT_SOURCE_DIR_ZYDIS=${zydisSrc}"
    # Zydis renamed this option to ZYAN_ZYCORE_PATH; the old name is silently ignored.
    "-DZYAN_ZYCORE_PATH=${zycoreSrc}"
    "-DFFMPEG_PREBUILT_DIR=${ffmpegPrebuilt}"
    "-DFETCHCONTENT_SOURCE_DIR_ZSTD=${zstdSrc}"
    "-DFETCHCONTENT_SOURCE_DIR_ZARCHIVE_SOURCE=${zarchiveSrc}"
  ];

  # Upstream's Ubuntu clang adds none of these, so drop them to match official builds.
  hardeningDisable = [
    "fortify"
    "stackprotector"
    "stackclashprotection"
    "zerocallusedregs"
    "strictoverflow"
  ];

  # upstream CMake target name, renamed to kyty-launcher in installPhase
  buildTargets = [ "launcher" ];

  # Upstream installs both binaries to the prefix root, so nothing reaches PATH and
  # the Qt wrapper hook never sees them.
  installPhase = ''
    runHook preInstall
    cmake --install . --prefix $out
    mkdir -p $out/bin
    # `launcher` is too generic for $out/bin, so publish it as kyty-launcher.
    mv $out/launcher $out/bin/kyty-launcher
    mv $out/kyty_emulator $out/bin/
    # Bundled deps (opus, zstd, zydis, xbyak) are linked statically; drop their headers.
    rm -rf $out/include $out/lib
    ${installDesktopEntry { inherit desktopItem desktopFile; }}
    runHook postInstall
  '';

  # SDL is linked statically, so it dlopens its window, Vulkan, audio and udev backends
  # and none is DT_NEEDED. Without them SDL picks the dummy audio driver: no sound.
  # Passed through the Qt wrapper so each binary gets one wrapper, not a chain.
  qtWrapperArgs = [
    "--prefix LD_LIBRARY_PATH : ${
      lib.makeLibraryPath [
        wayland
        vulkan-loader
        libx11
        libxcursor
        libxext
        libxfixes
        libxi
        libxrandr
        libxscrnsaver
        libxtst
        libxkbcommon
        libpulseaudio
        alsa-lib
        udev
        dbus
      ]
    }"
  ];

  meta = with lib; {
    description = "Free and open-source PlayStation 5 emulator";
    homepage = "https://github.com/KytyPS5/KytyPS5";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
  };
}
