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
          UTILIZATION="$((100-$(vmstat 1 2|tail -1|awk '{print $15}')))"
          CPU_THRESOLD=${toString (watcher.threshold)}

          if (( UTILIZATION > CPU_THRESOLD )) then
              printf true
          else
              printf false
          fi
        '')
      ];
  }) cfg.users;
}
