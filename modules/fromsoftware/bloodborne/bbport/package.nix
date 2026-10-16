{
  bubblewrap,
  channel ? "stable",
  fetchurl,
  lib,
  makeDesktopItem,
  runtimeShell,
  stdenvNoCC,
}:

let
  # Pins refreshed by ./update.sh, one per release channel.
  source = (builtins.fromJSON (builtins.readFile ./source.json)).${channel};

  desktopItem = makeDesktopItem {
    name = "bbport";
    desktopName = "Bloodborne";
    comment = "Native Bloodborne port launcher";
    exec = "bbport";
    icon = "applications-games";
    categories = [ "Game" ];
  };
in
stdenvNoCC.mkDerivation {
  pname = "bbport";
  inherit (source) version;

  src = fetchurl {
    inherit (source) url hash;
  };

  dontUnpack = true;

  # Stripping or patching the AppImage runtime would break the appended image.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/libexec/bbport/Bloodborne-bbport-x86_64.AppImage
    install -Dm755 ${./wrapper.sh} $out/bin/bbport
    substituteInPlace $out/bin/bbport \
      --subst-var-by shell ${runtimeShell} \
      --subst-var-by bwrap ${lib.getExe bubblewrap} \
      --subst-var-by appimage $out/libexec/bbport/Bloodborne-bbport-x86_64.AppImage
    install -Dm644 ${desktopItem}/share/applications/bbport.desktop -t $out/share/applications

    runHook postInstall
  '';

  meta = {
    description = "Native Linux port of Bloodborne (bring your own v1.09 dump)";
    homepage = "https://github.com/deadinside28/bloodborne_pc";
    license = lib.licenses.gpl2Only;
    mainProgram = "bbport";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
