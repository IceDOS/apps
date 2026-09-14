{ icedosLib, lib }:

let
  inherit (icedosLib)
    mkBoolOption
    mkEnumOption
    mkFloatBetweenOption
    mkIntBetweenOption
    mkStrOption
    ;

  inherit (lib) importTOML;

  inherit ((importTOML ./config.toml).icedos.applications.steam.headless-session)
    main
    secondary
    gamescope
    session
    ;
in
{
  # The SECOND, independent Sunshine daemon streaming the headless gamescope session;
  # the primary stays stock.

  main = {
    # Inject the normal Steam session (default HOME/account/library).
    enable = mkBoolOption { default = main.enable; };
  };

  secondary = {
    # Inject a second Steam session under secondary.path (separate account/library).
    enable = mkBoolOption { default = secondary.enable; };

    # HOME for the second session; REQUIRED when secondary.enable = true.
    path = mkStrOption { default = secondary.path; };
  };

  gamescope = {
    # Gamescope --rt (realtime SCHED_FIFO; needs the cap_sys_nice wrapper). Off = only SetNice(-20).
    realtime = mkBoolOption { default = gamescope.realtime; };

    # Each patch forces a local rebuild, so each is its own option; even all-off is
    # still rebuilt (gamescopePkg's always-on Steam-overlay postPatch).
    preferDiscreteGpu = mkBoolOption { default = gamescope.preferDiscreteGpu; };

    # HDR-capable gamescope (HDR/colorimetry patches); stream HDR follows the client per-stream.
    hdr = mkBoolOption { default = gamescope.hdr; };

    # Render Proton Wayland games natively (instead of via Xwayland); inert unless steamOS=true
    # (the baselayer driver lives in the steamos branch of the wait loop).
    nativeWayland = mkBoolOption { default = gamescope.nativeWayland; };

    # Forward Moonlight keyboard/mouse via inputtino passthrough + composite the X cursor
    # into the stream (the capture never composites it otherwise). One feature, one option.
    inputInjection = mkBoolOption { default = gamescope.inputInjection; };

    # Color management: Steam's Display color controls.
    colorManagement = mkBoolOption { default = gamescope.colorManagement; };

    # Gamescope render size, upscaled to output; 0 renders at the output resolution.
    renderWidth = mkIntBetweenOption {
      path = "icedos.applications.steam.headless-session.gamescope.renderWidth";
      source = ./config.toml;
      default = gamescope.renderWidth;
    } 0 8192;

    renderHeight = mkIntBetweenOption {
      path = "icedos.applications.steam.headless-session.gamescope.renderHeight";
      source = ./config.toml;
      default = gamescope.renderHeight;
    } 0 8192;

    # SDR-on-HDR tuning: brightness (--hdr-sdr-content-nits) and gamut stretch.
    sdrContentNits = mkIntBetweenOption {
      path = "icedos.applications.steam.headless-session.gamescope.sdrContentNits";
      source = ./config.toml;
      default = gamescope.sdrContentNits;
    } 0 10000;

    sdrGamutWideness = mkFloatBetweenOption {
      path = "icedos.applications.steam.headless-session.gamescope.sdrGamutWideness";
      source = ./config.toml;
      default = gamescope.sdrGamutWideness;
    } 0 1;

    # Gamescope upscaler (-F) and sharpness (--fsr-sharpness; fsr/nis only).
    upscaleFilter =
      mkEnumOption
        {
          path = "icedos.applications.steam.headless-session.gamescope.upscaleFilter";
          source = ./config.toml;
          default = gamescope.upscaleFilter;
        }
        [
          ""
          "fsr"
          "nis"
          "linear"
          "nearest"
          "pixel"
        ];

    fsrSharpness = mkIntBetweenOption {
      path = "icedos.applications.steam.headless-session.gamescope.fsrSharpness";
      source = ./config.toml;
      default = gamescope.fsrSharpness;
    } 0 20;

    # Seconds with no gamescope at all (teardown, crash, manual stop) before the minimal
    # 1x1x1 probe gamescope is rerun so Sunshine's display probe keeps passing. 0 = off.
    regrowTimeout = mkIntBetweenOption {
      path = "icedos.applications.steam.headless-session.gamescope.regrowTimeout";
      source = ./config.toml;
      default = gamescope.regrowTimeout;
    } 0 86400;
  };

  session = {
    # Freeze the per-session Steam cgroup (SIGSTOP) ~10s after the last client disconnects;
    # thaw on reconnect. Off = keep running idle.
    pauseOnDisconnect = mkBoolOption { default = session.pauseOnDisconnect; };

    # Seconds with no active stream before the session is torn down (injected Steam +
    # the full gamescope); the minimal probe gamescope regrows on its own timer. 0 = off.
    idleTimeout = mkIntBetweenOption {
      path = "icedos.applications.steam.headless-session.session.idleTimeout";
      source = ./config.toml;
      default = session.idleTimeout;
    } 0 86400;

    controllers = {
      # Keep host physical controllers out of the injected Steam (see scripts.nix).
      excludeHost = mkBoolOption { default = session.controllers.excludeHost; };

      # Hide the Sunshine virtual pad from the host desktop (see scripts.nix).
      isolateVirtual = mkBoolOption { default = session.controllers.isolateVirtual; };
    };

    steam = {
      # Steam -steamos3: Steam manages gamescope focus natively (no appid tagger) and
      # takes over host Bluetooth.
      steamOS = mkBoolOption { default = session.steam.steamOS; };

      # MangoHud overlay: --mangoapp on the idle gamescope + STEAM_USE_MANGOAPP=1 on Steam.
      mangoApp = mkBoolOption { default = session.steam.mangoApp; };
    };

    sunshine = {
      # Start at the graphical session (like the primary's autoStart); false = manual.
      autoStart = mkBoolOption { default = session.sunshine.autoStart; };

      # desktopShortcut: app-menu entry that starts the headless daemon (portal +
      # idle gamescope gate); the overlay derives it from the shipped shortcut.
      desktopShortcut = mkBoolOption { default = session.sunshine.desktopShortcut; };

      # mDNS label; must differ from the primary.
      name = mkStrOption { default = session.sunshine.name; };

      # Base port for the headless instance (primary uses 47989); Sunshine derives its whole block from it.
      port = mkIntBetweenOption {
        path = "icedos.applications.steam.headless-session.session.sunshine.port";
        source = ./config.toml;
        default = session.sunshine.port;
      } 1024 65535;

      # Open the headless instance's derived TCP/UDP port block in the host firewall.
      openFirewall = mkBoolOption { default = session.sunshine.openFirewall; };
    };
  };
}
