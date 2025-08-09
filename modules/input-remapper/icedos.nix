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
          inherit (lib) mapAttrs;
          users = config.icedos.system.users;
        in
        {
          services.input-remapper.enable = true;

          home-manager.users = mapAttrs (user: _: {
            systemd.user.services.input-remapper-autoload-fix = {
              Unit.Description = "Input Remapper Autoload Fix";
              Install.WantedBy = [ "graphical-session.target" ];

              Service = {
                ExecStart = "${pkgs.input-remapper}/bin/input-remapper-control --command autoload";
                Nice = "-20";
                Restart = "on-failure";
                StartLimitIntervalSec = 60;
                StartLimitBurst = 60;
              };
            };

          }) users;

          users.users = mapAttrs (user: _: { extraGroups = [ "input" ]; }) users;
        }
      )
    ];

  meta.name = "input-remapper";
}
