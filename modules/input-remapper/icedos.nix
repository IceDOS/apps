{ icedosLib, ... }:

{
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
          inherit (config.icedos) users;
          inherit (icedosLib.users) mkGroupInjector;
        in
        {
          services.input-remapper.enable = true;

          home-manager.sharedModules = [
            {
              systemd.user.services.input-remapper-autoload-fix = {
                Unit = {
                  Description = "Input Remapper Autoload Fix";
                  StartLimitIntervalSec = 60;
                  StartLimitBurst = 60;
                };

                Install.WantedBy = [ "graphical-session.target" ];

                Service = {
                  ExecStart = "${pkgs.input-remapper}/bin/input-remapper-control --command autoload";
                  Nice = "-20";
                  Restart = "on-failure";
                };
              };
            }
          ];

          users.users = mkGroupInjector "input" users;
        }
      )
    ];

  meta.name = "input-remapper";
}
