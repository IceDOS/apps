{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) mapAttrs mkIf;
  cfg = config.icedos;
in
{
  home-manager.users = mapAttrs (user: _: {
    home.packages =
      let
        watcher = cfg.applications.sd-inhibitor.users.${user}.watchers.cpu;
      in
      mkIf (watcher.enable) [
        (pkgs.writeShellScriptBin "cpu-watcher" ''
          vmstat 1 2 | awk -v t=${toString watcher.threshold} 'END { print (100 - $15 > t ? "true" : "false") }'
        '')
      ];
  }) cfg.users;
}
