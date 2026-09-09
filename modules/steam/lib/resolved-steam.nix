# `raw` is unmodified nixpkgs Steam, for modules that define programs.steam.*.
# `resolved` reads those options, so only modules that do not define them may use it.
{ config, pkgs }:
let
  raw = pkgs.steam;

  # Same override as steamBase in steam/icedos.nix, so both land on one store path.
  withExtras = raw.override {
    extraPkgs = _: config.programs.steam.extraPackages;
  };
in
{
  inherit raw;

  # No wrapSteamos3 here: that wrap is desktop-only, and the headless session passes
  # -steamos3 through steamos-session-select.
  resolved =
    if config.programs.steam.enable then
      config.programs.steam.package
    else if config.programs.steam.extraPackages != [ ] then
      # Steam is off (headless session), so build an FHS env carrying extraPackages
      # to keep launch-option helpers present in the container's /usr.
      withExtras
    else
      raw;
}
