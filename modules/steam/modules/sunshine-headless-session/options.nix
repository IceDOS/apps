{ icedosLib, lib }:

let
  inherit (icedosLib)
    mkBoolOption
    mkEnumOption
    mkFloatBetweenOption
    mkIntBetweenOption
    mkNonEmptyStrOption
    mkStrOption
    ;

  inherit (lib) readFile;

  inherit ((fromTOML (readFile ./config.toml)).icedos.applications.steam.headlessSession)
    colorManagement
    height
    excludeHostControllers
    hdr
    sdr
    isolateVirtualControllers
    normalSteamSession
    secondarySteamSession
    secondarySteamSessionPath
    refresh
    renderHeight
    renderWidth
    sdrContentNits
    sdrGamutWideness
    steamOS
    upscaleFilter
    fsrSharpness
    width
    ;
in
{
  # Required, host-specific — error out if left empty.
  width = mkNonEmptyStrOption { default = width; };
  height = mkNonEmptyStrOption { default = height; };

  # Keep host physical controllers out of the injected Steam (see scripts.nix).
  excludeHostControllers = mkBoolOption { default = excludeHostControllers; };

  # Hide the Sunshine virtual pad from the host desktop (see scripts.nix).
  isolateVirtualControllers = mkBoolOption { default = isolateVirtualControllers; };

  # Which Steam apps to inject. normal = default HOME; second = a separate account
  # under secondarySteamSessionPath (required non-empty when enabled).
  normalSteamSession = mkBoolOption { default = normalSteamSession; };
  secondarySteamSession = mkBoolOption { default = secondarySteamSession; };
  secondarySteamSessionPath = mkStrOption { default = secondarySteamSessionPath; };

  # Gamescope render size (upscaled to width/height). Empty → render at output res.
  renderWidth = mkStrOption { default = renderWidth; };
  renderHeight = mkStrOption { default = renderHeight; };

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

  # Which apps to expose per HDR mode. Both may be on — the single headless
  # gamescope's mode is switched per-app at stream start.
  sdr = mkBoolOption { default = sdr; };
  hdr = mkBoolOption { default = hdr; };

  # Output refresh (Hz): gamescope -r for the headless mode.
  refresh = mkIntBetweenOption {
    path = "icedos.applications.steam.headlessSession.refresh";
    source = ./config.toml;
    default = refresh;
  } 1 360;

  # Steam -steamos3: Steam manages baselayer/focus natively, eliminating the
  # need for the manual appid tagger in the wait loop.
  steamOS = mkBoolOption { default = steamOS; };

  # Color management: expose color controls in Steam's Display settings.
  colorManagement = mkBoolOption { default = colorManagement; };
}
