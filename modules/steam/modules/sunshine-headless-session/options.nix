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

  inherit ((fromTOML (readFile ./config.toml)).icedos.applications.steam.headlessSession)
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
    path = "icedos.applications.steam.headlessSession.renderWidth";
    source = ./config.toml;
    default = renderWidth;
  } 0 8192;

  renderHeight = mkIntBetweenOption {
    path = "icedos.applications.steam.headlessSession.renderHeight";
    source = ./config.toml;
    default = renderHeight;
  } 0 8192;

  # SDR-on-HDR tuning: brightness (--hdr-sdr-content-nits) and gamut stretch
  # (--sdr-gamut-wideness, 0 = none .. 1 = full BT.2020).
  sdrContentNits = mkIntBetweenOption {
    path = "icedos.applications.steam.headlessSession.sdrContentNits";
    source = ./config.toml;
    default = sdrContentNits;
  } 0 10000;

  sdrGamutWideness = mkFloatBetweenOption {
    path = "icedos.applications.steam.headlessSession.sdrGamutWideness";
    source = ./config.toml;
    default = sdrGamutWideness;
  } 0 1;

  # Gamescope upscaler (-F) and its sharpness (--fsr-sharpness; fsr/nis only).
  upscaleFilter =
    mkEnumOption
      {
        path = "icedos.applications.steam.headlessSession.upscaleFilter";
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
    path = "icedos.applications.steam.headlessSession.fsrSharpness";
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
}
