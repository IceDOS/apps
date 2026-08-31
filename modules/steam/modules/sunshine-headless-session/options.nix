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
    nativeWayland
    name
    normalSteamSession
    openFirewall
    pauseOnDisconnect
    port
    preferDiscreteGpu
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
  # the primary stays stock.

  # Start at the graphical session (like the primary's autoStart); false = manual.
  autoStart = mkBoolOption { default = autoStart; };

  # mDNS label; must differ from the primary.
  name = mkStrOption { default = name; };

  # Base port for the headless instance (primary uses 47989); Sunshine derives its whole block from it.
  port = mkIntBetweenOption {
    path = "icedos.applications.steam.headless-session.port";
    source = ./config.toml;
    default = port;
  } 1024 65535;

  # Open the headless instance's derived TCP/UDP port block in the host firewall.
  openFirewall = mkBoolOption { default = openFirewall; };

  # Freeze the per-session Steam cgroup (SIGSTOP) ~10s after the last client disconnects;
  # thaw on reconnect. Off = keep running idle.
  pauseOnDisconnect = mkBoolOption { default = pauseOnDisconnect; };

  # Keep host physical controllers out of the injected Steam (see scripts.nix).
  excludeHostControllers = mkBoolOption { default = excludeHostControllers; };

  # Hide the Sunshine virtual pad from the host desktop (see scripts.nix).
  isolateVirtualControllers = mkBoolOption { default = isolateVirtualControllers; };

  # normal = default HOME; second = separate account under secondarySteamSessionPath.
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

  # Each patch forces a local rebuild, so each is its own option; even all-off is
  # still rebuilt (gamescopePkg's always-on Steam-overlay postPatch).
  preferDiscreteGpu = mkBoolOption { default = preferDiscreteGpu; };

  # HDR-capable gamescope (HDR/colorimetry patches); stream HDR follows the client per-stream.
  hdr = mkBoolOption { default = hdr; };

  # Render Proton Wayland games natively (instead of via Xwayland); inert unless steamOS=true
  # (the baselayer driver lives in the steamos branch of the wait loop).
  nativeWayland = mkBoolOption { default = nativeWayland; };

  # Forward Moonlight keyboard/mouse via inputtino passthrough + composite the X cursor
  # into the stream (the capture never composites it otherwise). One feature, one option.
  inputInjection = mkBoolOption { default = inputInjection; };

  # Steam -steamos3: Steam manages gamescope focus natively (no appid tagger) and
  # takes over host Bluetooth.
  steamOS = mkBoolOption { default = steamOS; };

  # MangoHud overlay: --mangoapp on the idle gamescope + STEAM_USE_MANGOAPP=1 on Steam.
  mangoApp = mkBoolOption { default = mangoApp; };

  # Color management: Steam's Display color controls.
  colorManagement = mkBoolOption { default = colorManagement; };
}
