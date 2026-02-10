{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          pkgs,
          lib,
          ...
        }:

        let
          inherit (lib) mapAttrs;
          cfg = config.icedos;
        in
        {
          environment.systemPackages = [ pkgs.btop ];

          home-manager.users = mapAttrs (user: _: {
            home.file.".config/btop/btop.conf" = {
              force = true;
              source = ./btop.conf;
            };
          }) cfg.users;
        }
      )
    ];

  meta.name = "btop";
}
