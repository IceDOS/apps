{ icedosLib, ... }:

{
  options.icedos.applications.git.users =
    let
      inherit (icedosLib) mkStrOption mkSubmoduleAttrsOption;
    in
    mkSubmoduleAttrsOption { default = { }; } {
      username = mkStrOption { default = ""; };
      email = mkStrOption { default = ""; };
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
          users = cfg.applications.git.users;
        in
        {
          home-manager.users = mapAttrs (user: _: {
            home.packages = [ pkgs.lazygit ];

            programs.git = {
              enable = true;
              userName = "${users.${user}.username}";
              userEmail = "${users.${user}.email}";
            };
          }) cfg.users;
        }
      )
    ];

  meta.name = "git";
}
