{ icedosLib, lib, ... }:

{
  options.icedos.applications.docker =
    let
      docker = (fromTOML (lib.fileContents ./config.toml)).icedos.applications.docker;
    in
    {
      daemonSettings = lib.mkOption { default = { }; };
      requireSudo = icedosLib.mkBoolOption { default = docker.requireSudo; };
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
          inherit (lib) mapAttrs mkIf;
          cfg = config.icedos;
        in
        {
          environment.systemPackages = [ pkgs.distrobox ];
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
