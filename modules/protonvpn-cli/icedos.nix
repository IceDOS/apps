{ icedosLib, lib, ... }:

{
  options.icedos.applications.protonvpn-cli.country =
    let
      inherit (lib) mkOption readFile types;
      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.protonvpn-cli) country;
    in
    mkOption {
      type = types.nonEmptyStr;
      default = country;
      description = "Country code for Proton VPN (required).";
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          pkgs,
          ...
        }:
        let
          cfg = config.icedos;

          inherit (cfg.applications.protonvpn-cli) country;

          sessionTargets = icedosLib.systemd.desktopSessionTargets cfg;
        in
        {
          home-manager.sharedModules = [
            {
              systemd.user.services.protonvpn-cli = {
                Unit = {
                  Description = "Proton VPN CLI";
                  After = [ "graphical-session.target" ] ++ sessionTargets;
                  PartOf = "graphical-session.target";
                  StartLimitIntervalSec = 60;
                  StartLimitBurst = 60;
                };

                Install.WantedBy = sessionTargets;

                Service = {
                  ExecStart = "${pkgs.writeShellScriptBin "protonvpn-service" ''
                    ${icedosLib.bash.exportSystemPath}

                    protonvpn connect --country ${country}

                  ''}/bin/protonvpn-service";

                  Nice = "-20";
                  Restart = "on-failure";
                };
              };
            }
          ];

          environment.systemPackages = [ pkgs.proton-vpn-cli ];
        }
      )
    ];

  meta.name = "protonvpn-cli";
}
