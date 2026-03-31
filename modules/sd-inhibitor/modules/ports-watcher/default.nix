{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    concatStringsSep
    mapAttrs
    mkIf
    length
    ;

  cfg = config.icedos;
in
{
  home-manager.users = mapAttrs (user: _: {
    home.packages =
      let
        isEmpty = x: (length x) < 0;
        watcher = cfg.applications.sd-inhibitor.users.${user}.watchers.ports;
        inbound = map (p: "sport = :${toString p}") watcher.inboundPorts;
        outbound = map (p: "dport = :${toString p}") watcher.outboundPorts;
        filter = concatStringsSep " or " (inbound ++ outbound);
        hasPorts = !isEmpty watcher.inboundPorts || !isEmpty watcher.outboundPorts;
      in
      mkIf (watcher.enable && hasPorts) [
        (pkgs.writeShellScriptBin "ports-watcher" ''
          if [ "$(ss -t state established state time-wait '( ${filter} )' | tail -n +2)" ]; then
            printf true
          else
            printf false
          fi
        '')
      ];
  }) cfg.users;
}
