{ ... }:

{
  inputs.aagl = {
    url = "github:ezKEa/aagl-gtk-on-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      inputs.aagl.nixosModules.default
      (
        {
          lib,
          ...
        }:
        let
          inherit (lib) readFile;

          inherit ((fromTOML (readFile ./config.toml)).icedos.applications.aagl)
            launchers
            ;
        in
        {
          nix.settings = inputs.aagl.nixConfig; # Set up Cachix

          programs = lib.listToAttrs (
            map (game: {
              name = game;
              value.enable = true;
            }) launchers # Adds launchers and /etc/hosts rules
          );
        }
      )
    ];

  meta.name = "aagl";
}
