# The Steam packages, produced in one place.
#
# `raw` is the unmodified nixpkgs Steam. This is what the `steam` module family
# DEFINES — `programs.steam.package` and the home-installed Steam — so it must
# never depend on config (a definer cannot read the option it is setting).
#
# `resolved` is what a bare `steam` actually runs at stream/exec time:
# `config.programs.steam.package` when nixpkgs' steam module is enabled, else
# `raw`. Reading that option runs nixpkgs' apply, which forces
# `hardware.graphics.{package,package32}` — options only defined when
# `hardware.graphics.enable = true`. That is guaranteed whenever this is
# forced: nixpkgs' own steam module sets `hardware.graphics.enable = true`
# (and enable32Bit) inside the SAME `config = mkIf cfg.enable` block that
# programs.steam.enable gates on. So `resolved` is always safe to READ, and a
# config that never enables hardware.graphics (e.g. a headless build box)
# never forces it. Only consumers READ `resolved`; a module that DEFINES
# programs.steam.package must use `raw` instead — reading `resolved` there
# would read the very option it is defining (self-reference).
#
# Reads only nixpkgs options + `pkgs.steam`, so it does not require the
# icedos `steam` module to be loaded.
{ config, pkgs }:
let
  raw = pkgs.steam;
in
{
  inherit raw;
  resolved = if config.programs.steam.enable then config.programs.steam.package else raw;
}
