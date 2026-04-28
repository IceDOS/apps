{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) mkIf;
  cfg = config.icedos;
in
{
  home-manager.sharedModules = [
    (
      { config, ... }:
      {
        home.packages =
          let
            watcher = cfg.applications.sd-inhibitor.users.${config.home.username}.watchers.cpu;
          in
          mkIf (watcher.enable) [
            (pkgs.writeShellScriptBin "cpu-watcher" ''
              vmstat 1 2 | awk -v t=${toString watcher.threshold} 'END { print (100 - $15 > t ? "true" : "false") }'
            '')
          ];
      }
    )
  ];
}
