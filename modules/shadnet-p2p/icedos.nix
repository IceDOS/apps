{ icedosLib, lib, ... }:

{
  options.icedos.applications.shadnet-p2p =
    let
      inherit (lib) importTOML;
      inherit ((importTOML ./config.toml).icedos.applications.shadnet-p2p)
        enable
        seamless
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
      # Run the server as a managed systemd unit. False = just install the binary.
      enable = mkBoolOption { default = enable; };

      # Bloodborne seamless co-op, off by default. Normal co-op works with a stock
      # shadPS4 client; seamless additionally needs the matching seamless client fork.
      seamless = mkBoolOption { default = seamless; };

      # IP to bind (0.0.0.0 = LAN reachable).
      host = mkStrOption { default = host; };

      # Writable state dir for db/shadnet.cfg/worlds.cfg/scoreboards.cfg (SHADNET_HOME).
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
          # StateDirectory only manages paths under /var/lib; anything else would
          # desync it from SHADNET_HOME under ProtectSystem=strict.
          stateDirOk = lib.hasPrefix "/var/lib/" stateDir;
          inherit (config.icedos.applications.shadnet-p2p)
            enable
            seamless
            host
            stateDir
            openFirewall
            userService
            ;

          pkg = pkgs.shadnet-p2p;

          # Seeded on first service start (never clobbers an edited shadnet.cfg).
          seededCfg = pkgs.writeText "shadnet.cfg" ''
            [General]
            Host=${host}
            BloodborneSeamlessCoop=${if seamless then "true" else "false"}
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
              # Both units bind the same ports; enabling both just breaks them.
              assertion = !(enable && userService);
              message = "icedos.applications.shadnet-p2p: enable and userService are mutually exclusive (same ports).";
            }
            {
              assertion = !enable || stateDirOk;
              message = "icedos.applications.shadnet-p2p: stateDir must live under /var/lib/ for the systemd StateDirectory to cover it.";
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
              # Seed state on first start only, then let the server own the files.
              # LAN-reachable network service: run unprivileged + sandboxed.
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
              # Qt drops qInfo logs when stderr is not a TTY (e.g. journald).
              Environment = [
                "SHADNET_HOME=${stateDir}"
                "QT_FORCE_STDERR_LOGGING=1"
              ];
              Restart = "on-failure";
              RestartSec = "3";
            };
          };

          # Per-user service via home-manager: same seed-once behavior, but the
          # state lives in ~/.local/share/shadnet (the server's own AppData
          # fallback), so manual terminal runs and the user unit share one config.
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
                  # No SHADNET_HOME needed: the binary's AppData fallback already
                  # resolves to ~/.local/share/shadnet for the running user.
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
