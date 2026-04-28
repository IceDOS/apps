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
            watcher = cfg.applications.sd-inhibitor.users.${config.home.username}.watchers.disk;
          in
          mkIf (watcher.enable) [
            (pkgs.writeShellScriptBin "disk-watcher" ''
              check_iostat() {
                ${pkgs.sysstat}/bin/iostat -d -m -y -z 1 1 | awk -v t=${toString watcher.threshold} '
                  /^Device/ { data=1; next }
                  data && NF >= 4 && ($3+0 > t || $4+0 > t) { hit=1; exit }
                  END { exit !hit }
                '
              }

              # zpool iostat reports ZFS-level bandwidth, bypassing ARC/TXG
              # buffering that hides activity from block-layer iostat.
              check_zpool() {
                command -v zpool &>/dev/null || return 1
                zpool iostat -Hpy 1 1 | awk -v t=${toString watcher.threshold} '
                  NF >= 7 && (($6+0)/1048576 > t || ($7+0)/1048576 > t) { hit=1; exit }
                  END { exit !hit }
                '
              }

              check_iostat & ip=$!
              check_zpool & zp=$!

              hit=false
              wait "$ip" && hit=true
              wait "$zp" && hit=true
              echo "$hit"
            '')
          ];
      }
    )
  ];
}
