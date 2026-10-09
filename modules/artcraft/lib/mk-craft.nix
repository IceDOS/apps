# Shared builder for the ArtCraft "Crafting Apps": wraps the prebuilt Linux release tarball.
{
  autoPatchelfHook,
  dbus,
  description,
  extraBuildInputs ? [ ],
  fetchurl,
  homepage ? "https://getartcraft.com/apps",
  lib,
  libGL,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libxkbcommon,
  makeWrapper,
  pname,
  source,
  stdenv,
  stdenvNoCC,
  vulkan-loader,
  wayland,
}:

let
  inherit (lib.importJSON source) version rev hashes;

  arch =
    {
      x86_64-linux = "x86_64";
      aarch64-linux = "aarch64";
    }
    .${stdenvNoCC.hostPlatform.system}
      or (throw "${pname}: unsupported system ${stdenvNoCC.hostPlatform.system}");

  # winit, wgpu and zbus dlopen these at runtime, so autoPatchelf cannot see them.
  runtimeLibs = [
    dbus.lib
    libGL
    libx11
    libxcb
    libxcursor
    libxi
    libxkbcommon
    vulkan-loader
    wayland
  ];
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/storytold/${pname}/releases/download/${rev}/${pname}-${version}-linux-${arch}.tar.gz";
    hash = hashes.${arch};
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [ stdenv.cc.cc.lib ] ++ extraBuildInputs;

  runtimeDependencies = runtimeLibs;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r bin share $out/
    runHook postInstall
  '';

  # The startup library check only looks at ldconfig and LD_LIBRARY_PATH, not RUNPATH.
  postFixup = ''
    wrapProgram $out/bin/${pname} --suffix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
  '';

  meta = {
    inherit description homepage;
    license = lib.licenses.asl20;
    mainProgram = pname;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
