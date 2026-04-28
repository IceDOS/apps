{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    concatStringsSep
    mkIf
    length
    ;

  cfg = config.icedos;
in
{
  home-manager.sharedModules = [
    (
      { config, ... }:
      {
        home.packages =
          let
            isEmpty = x: (length x) < 0;
            watcher = cfg.applications.sd-inhibitor.users.${config.home.username}.watchers.ports;
            inbound = map (p: "sport = :${toString p}") watcher.inboundPorts;
            outbound = map (p: "dport = :${toString p}") watcher.outboundPorts;
            filter = concatStringsSep " or " (inbound ++ outbound);
            hasPorts = !isEmpty watcher.inboundPorts || !isEmpty watcher.outboundPorts;
          in
          mkIf (watcher.enable && hasPorts) [
            (pkgs.writeShellScriptBin "ports-watcher" ''
              # Stage 1: connection-oriented — TCP ESTAB/TIME-WAIT or UDP with connect().
              if [ "$(ss -tu state established state time-wait '( ${filter} )' | tail -n +2)" ]; then
                printf true
                exit
              fi

              # Stage 2: connectionless UDP — Wolf et al. bind() without connect(),
              # so sockets stay UNCONN; only transient Send-Q/Recv-Q reveals traffic.
              for _ in $(seq 1 33); do
                if ss -uan '( ${filter} )' | awk 'NR>1 && ($2+$3>0) {f=1} END{exit !f}'; then
                  printf true
                  exit
                fi
                sleep 0.03
              done

              printf false
            '')
          ];
      }
    )
  ];
}
