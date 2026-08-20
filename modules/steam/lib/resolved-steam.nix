# `raw`: unmodified nixpkgs Steam (for DEFINING options).
# `resolved`: config.programs.steam.package when enabled, else raw.
{ config, pkgs }:
let
  raw = pkgs.steam;
in
{
  inherit raw;
  resolved = if config.programs.steam.enable then config.programs.steam.package else raw;
}
