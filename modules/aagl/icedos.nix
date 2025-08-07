{ ... }:

{
  options = { };

  inputs.aagl = {
    url = "github:ezKEa/aagl-gtk-on-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      inputs.aagl.nixosModules.default

      {
        nix.settings = inputs.aagl.nixConfig; # Set up Cachix
        programs.anime-game-launcher.enable = true; # Adds launcher and /etc/hosts rules
      }
    ];

  meta = {
    name = "aagl";
    depends = [ ];
  };
}
