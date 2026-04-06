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
            programs.bash.enable = true;
          }) cfg.users;

          security.sudo.extraConfig = "Defaults pwfeedback"; # Show asterisks when typing sudo password
        }
      )
    ];

  meta.name = "bash";
}
