{ icedosLib, lib, ... }:

{
  options.icedos.applications.protonvpn-cli.country =
    let
      inherit (icedosLib) mkStrOption;
      inherit (lib) readFile;
      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.protonvpn-cli) country;
    in
    mkStrOption { default = country; };

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
          inherit (config.icedos) applications desktop users;
          inherit (applications.protonvpn-cli) country;

          inherit (lib)
            hasAttr
            mapAttrs
            optional
            ;
        in
        {
          home-manager.users = mapAttrs (
            user: _:
            let
              generateTargetArray =
                base:
                base
                ++ optional (hasAttr "cosmic" desktop) "cosmic-session.target"
                ++ optional (hasAttr "gnome" desktop) "gnome-session.target"
                ++ optional (hasAttr "hyprland" desktop) "hyprland-session.target";
            in
            {
              systemd.user.services.protonvpn-cli = {
                Unit = {
                  Description = "Proton VPN CLI";
                  After = generateTargetArray [ "graphical-session.target" ];
                  PartOf = "graphical-session.target";
                };

                Install.WantedBy = generateTargetArray [ ];

                Service = {
                  ExecStart = "${pkgs.writeShellScriptBin "protonvpn-service" ''
                    base_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                    nix_system_path="/run/current-system/sw/bin"
                    nix_user_path="''${HOME}/.nix-profile/bin"
                    export PATH="''${base_path}:''${nix_system_path}:''${nix_user_path}:$PATH"

                    protonvpn connect --country ${
                      let
                        inherit (icedosLib) abortIf;
                      in
                      if (abortIf (country == "") "protonvpn cli country option has to be set!") then country else ""
                    }

                  ''}/bin/protonvpn-service";

                  Nice = "-20";
                  Restart = "on-failure";
                  StartLimitBurst = 60;
                };
              };
            }
          ) users;

          environment.systemPackages = [ pkgs.proton-vpn-cli ];
        }
      )
    ];

  meta.name = "protonvpn-cli";
}
