{ ... }:
{
  inputs = {
    elephant = {
      override = true;
      url = "github:abenz1267/elephant";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    walker = {
      url = "github:abenz1267/walker";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.elephant.follows = "elephant";
    };
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      inputs.walker.nixosModules.default

      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          inherit (config.icedos) users;
          inherit (lib) mapAttrs readFile replaceStrings;

          walkerBin = inputs.walker.packages.${pkgs.stdenv.system}.default;
        in
        {
          programs.walker = {
            enable = true;

            config = {
              force_keyboard_focus = true;
              theme = "theme";
            };

            themes."theme".style =
              replaceStrings [ "1f1f28" "54546d" "f2ecbc" ] [ "1D1D20" "2E2E32" "EAEAEF" ]
                (readFile "${walkerBin.src}/resources/themes/default/style.css");
          };

          services.elephant = {
            enable = true;

            providers = [
              "desktopapplications"
              "clipboard"
              "symbols"
            ];
          };

          home-manager.users = mapAttrs (user: _: {
            systemd.user.services.walker = {
              Unit.Description = "Walker - Application Runner";
              Install.WantedBy = [ "graphical-session.target" ];

              Service = {
                ExecStart = "${pkgs.writeShellScriptBin "walker-service" ''
                  base_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                  nix_system_path="/run/current-system/sw/bin"
                  nix_user_path="''${HOME}/.nix-profile/bin"
                  export PATH="''${base_path}:''${nix_system_path}:''${nix_user_path}:$PATH"

                  elephant &

                  while :; do
                    walker --gapplication-service || echo 'walker crashed unexpectedly!'
                  done
                ''}/bin/walker-service";

                Nice = "-20";
                Restart = "on-failure";
                StartLimitIntervalSec = 60;
                StartLimitBurst = 60;
              };
            };
          }) users;

          environment.systemPackages =
            let
              inherit (pkgs) writeShellScriptBin;
            in
            [
              (writeShellScriptBin "walker-applications" ''
                walker -t theme -m desktopapplications
              '')

              (writeShellScriptBin "walker-clipboard" ''
                walker -t theme -m clipboard
              '')

              (writeShellScriptBin "walker-emojis" ''
                walker -t theme -m symbols
              '')
            ];

          environment.sessionVariables.COSMIC_DATA_CONTROL_ENABLED = 1;
        }
      )
    ];

  meta.name = "walker";
}
