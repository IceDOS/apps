# `raw`: unmodified nixpkgs Steam (for DEFINING options).
# `resolved`: config.programs.steam.package when enabled. When Steam is NOT
# enabled (the headless session), build an FHS env with the configured
# extraPackages so launch-option helpers exist in the container's /usr.
#
# Invariant: `resolved` reads (recurses on) programs.steam options, so it must
# only be used by modules that do NOT define `programs.steam.*` (the headless
# session). Any module that DEFINES programs.steam.* (steam/icedos.nix) must use
# `raw`, never `resolved`.
{ config, pkgs }:
let
  raw = pkgs.steam;

  # Mirror steamBase (steam/icedos.nix) deterministically -> same store path.
  # steamFinal = wrapSteamos3 steamBase is DESKTOP-only; the headless session
  # passes -steamos3 via steamos-session-select, so `resolved` omits that wrap.
  withExtras = raw.override {
    extraPkgs = _: config.programs.steam.extraPackages;
  };
in
{
  inherit raw;
  resolved =
    if config.programs.steam.enable then
      config.programs.steam.package
    else if config.programs.steam.extraPackages != [ ] then
      withExtras
    else
      raw;
}
