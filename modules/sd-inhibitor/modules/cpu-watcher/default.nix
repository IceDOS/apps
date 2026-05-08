{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) mkIf;
  inherit (config.icedos.applications) sd-inhibitor;
in
{
  home-manager.sharedModules = [
    (
      { config, ... }:
      {
        home.packages =
          let
            watcher = sd-inhibitor.users.${config.home.username}.watchers.cpu;
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
