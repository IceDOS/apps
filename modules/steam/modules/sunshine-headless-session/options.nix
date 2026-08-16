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
    autoStart
    colorManagement
    excludeHostControllers
    hdr
    inputInjection
    isolateVirtualControllers
    mangoApp
    name
    normalSteamSession
    openFirewall
    pauseOnDisconnect
    port
    secondarySteamSession
    secondarySteamSessionPath
    renderHeight
    renderWidth
    sdrContentNits
    sdrGamutWideness
    steamOS
    upscaleFilter
    fsrSharpness
    ;
in
{
  # The SECOND, independent Sunshine daemon streaming the headless gamescope session;
  # the primary stays stock/normal (see daemon.nix).

  # Start the daemon at the graphical session (like the primary's autoStart); false = manual.
  autoStart = mkBoolOption { default = autoStart; };

  # sunshine_name / mDNS label of the headless instance; must differ from the primary.
  name = mkStrOption { default = name; };

  # Base port for the headless instance (primary uses 47989); Sunshine derives its whole block from it.
  port = mkIntBetweenOption {
    path = "icedos.applications.steam.headless-session.port";
    source = ./config.toml;
    default = port;
  } 1024 65535;

  # Open the headless instance's derived TCP/UDP port block in the host firewall.
  openFirewall = mkBoolOption { default = openFirewall; };

  # Pause the headless session when the last client disconnects: systemd-freeze the
  # per-session Steam cgroup (SIGSTOP) after ~10s without a stream, thaw on reconnect.
  # Off = the session keeps running idle after a disconnect (upstream behavior).
  pauseOnDisconnect = mkBoolOption { default = pauseOnDisconnect; };

  # Keep host physical controllers out of the injected Steam (see scripts.nix).
  excludeHostControllers = mkBoolOption { default = excludeHostControllers; };

  # Hide the Sunshine virtual pad from the host desktop (see scripts.nix).
  isolateVirtualControllers = mkBoolOption { default = isolateVirtualControllers; };

  # Which Steam apps to inject: normal = default HOME; second = separate account
  # under secondarySteamSessionPath (required non-empty when enabled).
  normalSteamSession = mkBoolOption { default = normalSteamSession; };
  secondarySteamSession = mkBoolOption { default = secondarySteamSession; };
  secondarySteamSessionPath = mkStrOption { default = secondarySteamSessionPath; };

  # Gamescope render size (upscaled to width/height). 0 -> render at output res.
  renderWidth = mkIntBetweenOption {
    path = "icedos.applications.steam.headless-session.renderWidth";
    source = ./config.toml;
    default = renderWidth;
  } 0 8192;

  renderHeight = mkIntBetweenOption {
    path = "icedos.applications.steam.headless-session.renderHeight";
    source = ./config.toml;
    default = renderHeight;
  } 0 8192;

  # SDR-on-HDR tuning: brightness (--hdr-sdr-content-nits) and gamut stretch.
  sdrContentNits = mkIntBetweenOption {
    path = "icedos.applications.steam.headless-session.sdrContentNits";
    source = ./config.toml;
    default = sdrContentNits;
  } 0 10000;

  sdrGamutWideness = mkFloatBetweenOption {
    path = "icedos.applications.steam.headless-session.sdrGamutWideness";
    source = ./config.toml;
    default = sdrGamutWideness;
  } 0 1;

  # Gamescope upscaler (-F) and sharpness (--fsr-sharpness; fsr/nis only).
  upscaleFilter =
    mkEnumOption
      {
        path = "icedos.applications.steam.headless-session.upscaleFilter";
        source = ./config.toml;
        default = upscaleFilter;
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
    path = "icedos.applications.steam.headless-session.fsrSharpness";
    source = ./config.toml;
    default = fsrSharpness;
  } 0 20;

  # HDR-capable gamescope (HDR/colorimetry patches). Whether a stream is actually
  # HDR follows the Moonlight client's setting per-stream, not this option.
  hdr = mkBoolOption { default = hdr; };

  # Forward Moonlight keyboard/mouse via Sunshine's inputtino passthrough devices.
  inputInjection = mkBoolOption { default = inputInjection; };

  # Steam -steamos3: Steam manages gamescope focus natively (no appid tagger) and
  # takes over host Bluetooth; the wait loop re-asserts the pre-launch BT state.
  steamOS = mkBoolOption { default = steamOS; };

  # MangoHud overlay: --mangoapp on the idle gamescope + STEAM_USE_MANGOAPP=1 on Steam.
  mangoApp = mkBoolOption { default = mangoApp; };

  # Color management: expose color controls in Steam's Display settings.
  colorManagement = mkBoolOption { default = colorManagement; };
}
