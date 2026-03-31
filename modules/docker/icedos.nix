{ icedosLib, lib, ... }:

{
  options.icedos.applications.docker =
    let
      inherit ((fromTOML (lib.fileContents ./config.toml)).icedos.applications.docker)
        daemonSettings
        requireSudo
        ;
    in
    {
      daemonSettings = lib.mkOption { default = daemonSettings; };
      requireSudo = icedosLib.mkBoolOption { default = requireSudo; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          ...
        }:

        let
          inherit (lib) mapAttrs mkIf;
          cfg = config.icedos;
        in
        {
          virtualisation.docker = {
            enable = true;
            daemon.settings = cfg.applications.docker.daemonSettings;
          };

          users.users = mapAttrs (user: _: {
            extraGroups = mkIf (!cfg.applications.docker.requireSudo) [ "docker" ];
          }) cfg.users;
        }
      )
    ];

  meta.name = "docker";
}
