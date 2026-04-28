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
          inherit (lib) mkIf;
        in
        {
          home-manager.sharedModules = [
            {
              programs.btop.enable = true;

              xdg.configFile."btop/btop.conf" = mkIf (!(config.stylix.enable or false)) {
                source = ./btop.conf;
                force = true;
              };
            }
          ];
        }
      )
    ];

  meta.name = "btop";
}
