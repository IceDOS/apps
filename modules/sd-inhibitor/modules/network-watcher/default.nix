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
        watcher = cfg.applications.sd-inhibitor.users.${user}.watchers.network;
      in
      mkIf (watcher.enable) [
        (pkgs.writeShellScriptBin "network-watcher" ''
          iface=$(ip -o route show default | awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1); exit}}')
          [[ -z "$iface" ]] && { echo false; exit; }

          sample() { awk -v i="$iface:" '$1==i {print $2, $10; exit}' /proc/net/dev; }

          read -r rx1 tx1 < <(sample)
          sleep 1
          read -r rx2 tx2 < <(sample)

          t=${toString watcher.threshold}
          if (( rx2 - rx1 > t || tx2 - tx1 > t )); then
            echo true
          else
            echo false
          fi
        '')
      ];
  }) cfg.users;
}
