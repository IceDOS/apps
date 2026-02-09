{ ... }:

{
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
          inherit (config.icedos) desktop users;

          inherit (lib)
            hasAttr
            mapAttrs
            optional
            readFile
            replaceStrings
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
              home.file = {
                ".config/walker/config.toml".text =
                  replaceStrings [ "force_keyboard_focus = false" ] [ "force_keyboard_focus = true" ]
                    (readFile "${pkgs.walker.src}/resources/config.toml");

                ".config/walker/themes/theme/style.css".text =
                  replaceStrings [ "1f1f28" "54546d" "f2ecbc" ] [ "1D1D20" "2E2E32" "EAEAEF" ]
                    (readFile "${pkgs.walker.src}/resources/themes/default/style.css");
              };

              systemd.user.services.walker = {
                Unit = {
                  Description = "Walker - Application Runner";

                  After = generateTargetArray [
                    "graphical-session.target"
                    "elephant.service"
                  ];

                  PartOf = "graphical-session.target";
                };

                Install.WantedBy = generateTargetArray [ ];

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
                  StartLimitBurst = 60;
                };
              };
            }
          ) users;

          environment.systemPackages =
            let
              inherit (pkgs) elephant walker writeShellScriptBin;
            in
            [
              elephant
              walker

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
