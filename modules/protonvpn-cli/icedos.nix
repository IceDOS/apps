{ lib, ... }:

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
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.icedos;

          inherit (cfg.applications.protonvpn-cli) country;

          inherit (lib)
            hasAttr
            optional
            ;

          generateTargetArray =
            base:
            base
            ++ optional (hasAttr "desktop" cfg && hasAttr "cosmic" cfg.desktop) "cosmic-session.target"
            ++ optional (hasAttr "desktop" cfg && hasAttr "gnome" cfg.desktop) "gnome-session.target"
            ++ optional (hasAttr "desktop" cfg && hasAttr "hyprland" cfg.desktop) "hyprland-session.target";
        in
        {
          home-manager.sharedModules = [
            {
              systemd.user.services.protonvpn-cli = {
                Unit = {
                  Description = "Proton VPN CLI";
                  After = generateTargetArray [ "graphical-session.target" ];
                  PartOf = "graphical-session.target";
                  StartLimitIntervalSec = 60;
                  StartLimitBurst = 60;
                };

                Install.WantedBy = generateTargetArray [ ];

                Service = {
                  ExecStart = "${pkgs.writeShellScriptBin "protonvpn-service" ''
                    base_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                    nix_system_path="/run/current-system/sw/bin"
                    nix_user_path="''${HOME}/.nix-profile/bin"
                    export PATH="''${base_path}:''${nix_system_path}:''${nix_user_path}:$PATH"

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
