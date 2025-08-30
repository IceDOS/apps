{ icedosLib, lib, ... }:

{
  options.icedos.applications.docker =
    let
      docker = (fromTOML (lib.fileContents ./config.toml)).icedos.applications.docker;
    in
    {
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
          virtualisation.docker.enable = true;

          users.users = mapAttrs (user: _: {
            extraGroups = mkIf (!cfg.applications.docker.requireSudo) [ "docker" ];
          }) cfg.users;
        }
      )
    ];

  meta.name = "docker";
}
