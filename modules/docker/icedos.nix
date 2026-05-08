{ icedosLib, lib, ... }:

{
  options.icedos.applications.docker =
    let
      inherit (icedosLib) mkAttrsOption mkBoolOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.docker)
        daemonSettings
        requireSudo
        ;
    in
    {
      daemonSettings = mkAttrsOption { default = daemonSettings; };
      requireSudo = mkBoolOption { default = requireSudo; };
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
          inherit (config.icedos) applications users;
          inherit (applications.docker) daemonSettings requireSudo;
        in
        {
          virtualisation.docker = {
            enable = true;
            daemon.settings = daemonSettings;
          };

          users.users = mapAttrs (_: _: {
            extraGroups = mkIf (!requireSudo) [ "docker" ];
          }) users;
        }
      )
    ];

  meta.name = "docker";
}
