{ icedosLib, ... }:

{
  options.icedos.system.users =
    let
      inherit (icedosLib) mkStrOption mkSubmoduleAttrsOption;
    in
    mkSubmoduleAttrsOption { } {
      description = mkStrOption { };
      type = mkStrOption { };

      applications = {
        git = {
          username = mkStrOption { };
          email = mkStrOption { };
        };
      };
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
          inherit (lib) mapAttrs;
          cfg = config.icedos;
        in
        {
          home-manager.users = mapAttrs (user: _: {
            home.packages = [ pkgs.lazygit ];

            programs.git = {
              enable = true;
              userName = "${cfg.system.users.${user}.applications.git.username}";
              userEmail = "${cfg.system.users.${user}.applications.git.email}";
            };
          }) cfg.system.users;
        }
      )
    ];

  meta.name = "git";
}
