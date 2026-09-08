{ icedosLib, lib, ... }:

{
  options.icedos.applications.shadnet-p2p =
    let
      inherit (lib) importTOML;
      inherit ((importTOML ./config.toml).icedos.applications.shadnet-p2p)
        enable
        seamless
        seamlessAnySummonType
        host
        stateDir
        openFirewall
        userService
        ;
      inherit (icedosLib)
        mkBoolOption
        mkStrOption
        ;
    in
    {
      # Run the server as a managed systemd unit. False installs the binary only.
      enable = mkBoolOption { default = enable; };

      # Bloodborne seamless co-op. Normal co-op works with a stock shadPS4 client;
      # seamless needs the matching seamless client fork.
      seamless = mkBoolOption { default = seamless; };

      # Seamless-only: match signs outside the searcher's SummonTypeList.
      seamlessAnySummonType = mkBoolOption { default = seamlessAnySummonType; };

      # IP to bind. 0.0.0.0 makes the server reachable on the LAN.
      host = mkStrOption { default = host; };

      # Writable state dir (SHADNET_HOME) for the database, config and score files.
      stateDir = mkStrOption { default = stateDir; };

      # Open the server's TCP/UDP/HTTP ports in the firewall.
      openFirewall = mkBoolOption { default = openFirewall; };

      # Per-user systemd unit via home-manager (state in ~/.local/share/shadnet).
      userService = mkBoolOption { default = userService; };
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
          inherit (lib) mkIf;
          inherit (config.icedos.applications.shadnet-p2p)
            enable
            seamless
            seamlessAnySummonType
            host
            stateDir
            openFirewall
            userService
            ;

          # StateDirectory gets baseNameOf stateDir, so a deeper path would create a
          # different directory than SHADNET_HOME and ReadWritePaths point at.
          stateDirOk = stateDir == "/var/lib/" + builtins.baseNameOf stateDir;

          pkg = pkgs.shadnet-p2p;

          # Seeded on first service start (never clobbers an edited shadnet.cfg).
          seededCfg = pkgs.writeText "shadnet.cfg" ''
            [General]
            Host=${host}
            BloodborneSeamlessCoop=${if seamless then "true" else "false"}
            BloodborneSeamlessAnySummonType=${if seamlessAnySummonType then "true" else "false"}
            Matching2Enabled=true
            UnsecuredPort=31313
            MatchingUdpPort=31314
            WebApiPort=31315
            StatsEnabled=true
            StatsPort=31320
          '';
        in
        {
          assertions = [
            {
              # Both units bind the same ports, so enabling both breaks them.
              assertion = !(enable && userService);
              message = "icedos.applications.shadnet-p2p: enable and userService are mutually exclusive (same ports).";
            }
            {
              assertion = !enable || stateDirOk;
              message = "icedos.applications.shadnet-p2p: stateDir must live under /var/lib/ for the systemd StateDirectory to cover it.";
            }
            {
              # The broker requires seamless co-op too, so the flag alone does nothing.
              assertion = !(enable || userService) || !seamlessAnySummonType || seamless;
              message = "icedos.applications.shadnet-p2p: seamlessAnySummonType needs seamless = true.";
            }
          ];

          nixpkgs.overlays = [
            (final: super: {
              shadnet-p2p = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkg ];

          systemd.services.shadnet-p2p = mkIf enable {
            description = "shadNet P2P server (Bloodborne co-op: ${if seamless then "seamless" else "normal"})";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];

            path = [ pkgs.coreutils ];

            serviceConfig = {
              Type = "simple";
              # LAN-reachable network service, so run it unprivileged and sandboxed.
              DynamicUser = true;
              StateDirectory = builtins.baseNameOf stateDir;
              ReadWritePaths = [ stateDir ];
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              NoNewPrivileges = true;

              RestrictAddressFamilies = [
                "AF_INET"
                "AF_INET6"
                "AF_UNIX"
              ];

              ExecStartPre = pkgs.writeShellScript "shadnet-seed" ''
                [ -e "${stateDir}/shadnet.cfg" ] || install -m 0644 "${seededCfg}" "${stateDir}/shadnet.cfg"
                for c in worlds.cfg scoreboards.cfg; do
                  [ -e "${stateDir}/$c" ] || install -m 0644 "${pkg}/bin/$c" "${stateDir}/$c"
                done
              '';
              ExecStart = "${pkg}/bin/shadnet";
              Environment = [
                "SHADNET_HOME=${stateDir}"
                # Without this Qt sends journald unformatted messages, losing the
                # timestamp and category prefix.
                "QT_FORCE_STDERR_LOGGING=1"
              ];
              Restart = "on-failure";
              RestartSec = "3";
            };
          };

          # Seeding works the same way here. State lives in ~/.local/share/shadnet,
          # the AppDataLocation fallback our postPatch adds, so terminal runs agree.
          home-manager.sharedModules = mkIf userService [
            {
              systemd.user.services.shadnet-p2p = {
                Unit = {
                  Description = "shadNet P2P server (Bloodborne co-op: ${if seamless then "seamless" else "normal"})";
                  After = [ "network.target" ];
                };

                Service = {
                  Type = "simple";
                  ExecStartPre = pkgs.writeShellScript "shadnet-seed-user" ''
                    state="$HOME/.local/share/shadnet"
                    mkdir -p "$state"
                    [ -e "$state/shadnet.cfg" ] || install -m 0644 "${seededCfg}" "$state/shadnet.cfg"
                    for c in worlds.cfg scoreboards.cfg; do
                      [ -e "$state/$c" ] || install -m 0644 "${pkg}/bin/$c" "$state/$c"
                    done
                  '';
                  ExecStart = "${pkg}/bin/shadnet";
                  # SHADNET_HOME is not needed because the AppDataLocation
                  # fallback already points at this directory.
                  Environment = [ "QT_FORCE_STDERR_LOGGING=1" ];
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
            31313
            31315
            31320
          ];

          networking.firewall.allowedUDPPorts = mkIf openFirewall [ 31314 ];
        }
      )
    ];

  meta.name = "shadnet-p2p";
}
