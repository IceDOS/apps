{
  stdenv,
  wayland,
  wayland-scanner,
  wayland-protocols,
  makeWrapper,
}:

stdenv.mkDerivation {
  pname = "sunshine-headless-lease";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    wayland-scanner
    makeWrapper
  ];
  buildInputs = [ wayland ];

  buildPhase = ''
    runHook preBuild

    xml=${wayland-protocols}/share/wayland-protocols/staging/drm-lease/drm-lease-v1.xml
    wayland-scanner client-header "$xml" drm-lease-v1-client-protocol.h
    wayland-scanner private-code   "$xml" drm-lease-v1-protocol.c

    # libseat LD_PRELOAD shim (exports the libseat ABI; no deps beyond libc)
    $CC -O2 -Wall -fPIC -shared -o libseat-dlm.so libseat-dlm.c

    # wp_drm_lease client + fork/exec orchestrator
    $CC -O2 -Wall -o lease-runner \
      lease-runner.c drm-lease-v1-protocol.c -lwayland-client

    # keep-light: minimal black xdg_toplevel that keeps gamescope lighting the
    # connector with no redraw (so the idle gamescope actually modesets HDMI-A-1).
    xdg=${wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
    wayland-scanner client-header "$xdg" xdg-shell-client-protocol.h
    wayland-scanner private-code   "$xdg" xdg-shell-protocol.c
    $CC -O2 -Wall -o keep-light \
      keep-light.c xdg-shell-protocol.c -lwayland-client

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 libseat-dlm.so $out/lib/libseat-dlm.so
    install -Dm755 keep-light     $out/bin/keep-light
    install -Dm755 lease-runner   $out/libexec/lease-runner

    makeWrapper $out/libexec/lease-runner $out/bin/lease-runner \
      --set-default LIBSEAT_DLM_SO $out/lib/libseat-dlm.so

    runHook postInstall
  '';

  meta.mainProgram = "lease-runner";
}
