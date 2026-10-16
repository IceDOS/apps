{ icedosLib, lib, ... }:

{
  options.icedos.applications.bbsc-gameserver =
    let
      inherit (lib) importTOML;
      inherit ((importTOML ./config.toml).icedos.applications.bbsc-gameserver)
        enable
        userService
        address
        shadnet
        host
        summonInterval
        levelRange
        stateDir
        openFirewall
        ;
      inherit (icedosLib)
        mkBoolOption
        mkNumberOption
        mkStrOption
        ;
    in
    {
      # Run the server as a managed systemd unit. False installs the binary only.
      enable = mkBoolOption { default = enable; };

      # Per-user systemd unit via home-manager (state in ~/.local/share/bbsc-gameserver).
      userService = mkBoolOption { default = userService; };

      # IPv4 address players reach this server at (server list and relay).
      address = mkStrOption { default = address; };

      # shadNet server for summons. Empty means `address`.
      shadnet = mkStrOption { default = shadnet; };

      # IP to bind. 0.0.0.0 makes the server reachable on the LAN.
      host = mkStrOption { default = host; };

      # Seconds between summon sign checks (vanilla 35).
      summonInterval = mkNumberOption { default = summonInterval; };

      # Co-op level window. 0 keeps vanilla's 20.
      levelRange = mkNumberOption { default = levelRange; };

      # Writable state dir (BBSC_GAMESERVER_HOME) for the system unit.
      stateDir = mkStrOption { default = stateDir; };

      # Open the game server, relay and bbhost ports in the firewall.
      openFirewall = mkBoolOption { default = openFirewall; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:

        let
          inherit (lib) escapeShellArgs mkIf optionals;
          inherit (config.icedos.applications.bbsc-gameserver)
            enable
            userService
            address
            shadnet
            host
            summonInterval
            levelRange
            stateDir
            openFirewall
            ;

          # StateDirectory gets baseNameOf stateDir, so a deeper path would create a
          # different directory than BBSC_GAMESERVER_HOME points at.
          stateDirOk = stateDir == "/var/lib/" + builtins.baseNameOf stateDir;

          pkg = pkgs.bbsc-gameserver;

          execStart = escapeShellArgs (
            [
              (lib.getExe pkg)
              "--shadnet"
              (if shadnet != "" then shadnet else address)
              "--host"
              host
              "--advertise"
              address
              "--summon-interval"
              (toString summonInterval)
              # Play-log uploads go to Amazon S3; nothing on a private server reads them.
              "--no-playlog"
            ]
            ++ optionals (levelRange > 0) [
              "--level-range"
              (toString levelRange)
            ]
          );

          description = "BBSC game server (Bloodborne seamless co-op)";
        in
        {
          assertions = [
            {
              # Both units bind the same ports, so enabling both breaks them.
              assertion = !(enable && userService);
              message = "icedos.applications.bbsc-gameserver: enable and userService are mutually exclusive (same ports).";
            }
            {
              assertion = !(enable || userService) || address != "";
              message = "icedos.applications.bbsc-gameserver: set address to the IP players reach this server at.";
            }
            {
              assertion = !enable || stateDirOk;
              message = "icedos.applications.bbsc-gameserver: stateDir must live under /var/lib/ for the systemd StateDirectory to cover it.";
            }
          ];

          nixpkgs.overlays = [
            (final: super: {
              bbsc-gameserver = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkg ];

          systemd.services.bbsc-gameserver = mkIf enable {
            inherit description;
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];

            serviceConfig = {
              Type = "simple";
              # LAN-reachable network service, so run it unprivileged and sandboxed.
              DynamicUser = true;
              StateDirectory = builtins.baseNameOf stateDir;
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              NoNewPrivileges = true;

              RestrictAddressFamilies = [
                "AF_INET"
                "AF_INET6"
              ];

              ExecStart = execStart;
              Environment = [ "BBSC_GAMESERVER_HOME=${stateDir}" ];
              Restart = "on-failure";
              RestartSec = "3";
            };
          };

          home-manager.sharedModules = mkIf userService [
            {
              systemd.user.services.bbsc-gameserver = {
                Unit = {
                  Description = description;
                  After = [ "network.target" ];
                };

                Service = {
                  Type = "simple";
                  ExecStart = execStart;
                  Restart = "on-failure";
                  RestartSec = "3";
                };

                Install = {
                  WantedBy = [ "default.target" ];
                };
              };
            }
          ];

          networking.firewall.allowedTCPPorts = mkIf openFirewall [
            18671
            20443
            20444
          ];

          networking.firewall.allowedUDPPorts = mkIf openFirewall [ 3478 ];

          icedos.system.tips.list = lib.optionals (enable || userService) [
            "Point the bbport launcher's game server at http://${address} and set BB_BBSC_LOCAL_SERVER=0."
          ];
        }
      )
    ];

  meta.name = "bbsc-gameserver";
}
