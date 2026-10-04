{
  fetchFromGitHub,
  lib,
  libGL,
  libX11,
  libXcursor,
  libXi,
  libXrandr,
  libxkbcommon,
  openssl,
  pkg-config,
  rustPlatform,
  vulkan-loader,
  wayland,
}:

let
  # Pin refreshed by ./update.sh.
  source = builtins.fromJSON (builtins.readFile ./source.json);

  # eframe dlopens its windowing and GL backends at runtime.
  runtimeLibs = [
    libGL
    libX11
    libXcursor
    libXi
    libXrandr
    libxkbcommon
    vulkan-loader
    wayland
  ];
in
rustPlatform.buildRustPackage {
  pname = "steam-cloud-file-manager";
  inherit (source) version cargoHash;

  src = fetchFromGitHub {
    owner = "Fldicoahkiin";
    repo = "SteamCloudFileManager";
    inherit (source) rev hash;
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  doCheck = false;

  # steamworks-sys drops its bundled libsteam_api.so in its build-script OUT_DIR.
  postInstall = ''
    install -Dm644 "$(find target -path "*/steamworks-sys-*/out/libsteam_api.so" -print -quit)" -t $out/lib
    mv $out/bin/SteamCloudFileManager $out/bin/steam-cloud-file-manager
    install -Dm644 assets/steam-cloud-file-manager.desktop -t $out/share/applications
    install -Dm644 assets/steam_cloud.svg \
      $out/share/icons/hicolor/scalable/apps/steam-cloud-file-manager.svg
  '';

  postFixup = ''
    patchelf --add-rpath ${lib.makeLibraryPath runtimeLibs} $out/bin/steam-cloud-file-manager
  '';

  meta = {
    description = "Manage and view Steam Cloud save files";
    homepage = "https://github.com/Fldicoahkiin/SteamCloudFileManager";
    license = lib.licenses.gpl3Only;
    mainProgram = "steam-cloud-file-manager";
    platforms = [ "x86_64-linux" ];
  };
}
