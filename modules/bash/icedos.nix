{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        home-manager.sharedModules = [
          { programs.bash.enable = true; }
        ];

        security.sudo.extraConfig = "Defaults pwfeedback"; # Show asterisks when typing sudo password
      }
    ];

  meta.name = "bash";
}
