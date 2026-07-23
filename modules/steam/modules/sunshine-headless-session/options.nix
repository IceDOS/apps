{ icedosLib, lib }:

let
  inherit (icedosLib)
    mkBoolOption
    mkEnumOption
    mkFloatBetweenOption
    mkIntBetweenOption
    mkStrOption
    ;

  inherit (lib) readFile;

  inherit ((fromTOML (readFile ./config.toml)).icedos.applications.steam.headless-session)
    colorManagement
    excludeHostControllers
    hdr
    isolateVirtualControllers
    mangoApp
    normalSteamSession
    secondarySteamSession
    secondarySteamSessionPath
    renderHeight
    renderWidth
    sdrContentNits
    sdrGamutWideness
    steamOS
    upscaleFilter
    fsrSharpness
    desktop-capture
    ;
in
{
  # Keep host physical controllers out of the injected Steam (see scripts.nix).
  excludeHostControllers = mkBoolOption { default = excludeHostControllers; };

  # Hide the Sunshine virtual pad from the host desktop (see scripts.nix).
  isolateVirtualControllers = mkBoolOption { default = isolateVirtualControllers; };

  # Which Steam apps to inject. normal = default HOME; second = a separate account
  # under secondarySteamSessionPath (required non-empty when enabled).
  normalSteamSession = mkBoolOption { default = normalSteamSession; };
  secondarySteamSession = mkBoolOption { default = secondarySteamSession; };
  secondarySteamSessionPath = mkStrOption { default = secondarySteamSessionPath; };

  # Gamescope render size (upscaled to width/height). 0 → render at output res.
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

  # SDR-on-HDR tuning: brightness (--hdr-sdr-content-nits) and gamut stretch
  # (--sdr-gamut-wideness, 0 = none .. 1 = full BT.2020).
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

  # Gamescope upscaler (-F) and its sharpness (--fsr-sharpness; fsr/nis only).
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

  # Make the headless gamescope HDR-capable (builds the HDR/colorimetry gamescope patches).
  # Whether a given stream is actually HDR follows the Moonlight client's HDR setting,
  # decided per-stream like resolution — this option no longer forces HDR on.
  hdr = mkBoolOption { default = hdr; };

  # Steam -steamos3 (SteamOS Deck UI mode): Steam manages the gamescope baselayer/
  # focus natively, eliminating the manual appid tagger in the wait loop. Also makes
  # Steam take over the host Bluetooth and power it off on launch — the wait loop
  # re-asserts the pre-launch BT state (see scripts.nix root-cause note).
  steamOS = mkBoolOption { default = steamOS; };

  # MangoHud performance overlay (mangoapp). Adds --mangoapp to the idle gamescope
  # (gamescope itself spawns/respawns + composites the mangoapp overlay window) and sets
  # STEAM_USE_MANGOAPP=1 on the injected Steam so the overlay level is driven from Steam's
  # Quick Access -> Performance menu.
  mangoApp = mkBoolOption { default = mangoApp; };

  # Color management: expose color controls in Steam's Display settings.
  colorManagement = mkBoolOption { default = colorManagement; };

  # Second, independent Sunshine instance that streams the REAL physical KDE Plasma
  # (Wayland) desktop (see desktop-capture.nix), coexisting with the headless gamescope
  # session. Separate daemon: its own ports and its own isolated pairing/state.
  desktop-capture = {
    enable = mkBoolOption { default = desktop-capture.enable; };

    # sunshine_name / mDNS name; must differ from the primary so Moonlight can tell them apart.
    name = mkStrOption { default = desktop-capture.name; };

    # Base port (primary uses 47989); Sunshine derives its whole TCP/UDP block from it.
    port = mkIntBetweenOption {
      path = "icedos.applications.steam.headless-session.desktop-capture.port";
      source = ./config.toml;
      default = desktop-capture.port;
    } 1024 65535;

    # portal = KDE Wayland ScreenCast (no caps); kms = raw DRM scanout (needs capSysAdmin).
    backend =
      mkEnumOption
        {
          path = "icedos.applications.steam.headless-session.desktop-capture.backend";
          source = ./config.toml;
          default = desktop-capture.backend;
        }
        [
          "portal"
          "kms"
        ];

    # Open the instance's derived TCP/UDP port block in the host firewall.
    openFirewall = mkBoolOption { default = desktop-capture.openFirewall; };

    # Optional specific monitor/output to capture (mainly for kms). Empty = default/portal picker.
    outputName = mkStrOption { default = desktop-capture.outputName; };
  };
}
