{ ... }:

{
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
          inherit (lib) mapAttrs;
          cfg = config.icedos;
        in
        {
          home-manager.users = mapAttrs (user: _: {
            programs.btop.enable = true;

            xdg.configFile."btop/btop.conf" = {
              source = ./btop.conf;
              force = true;
            };
          }) cfg.users;
        }
      )
    ];

  meta.name = "btop";
}
