{ ... }:

{
  inputs.nix-alien = {
    url = "github:thiagokokada/nix-alien";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      {
        environment.systemPackages = [
          inputs.nix-alien.packages."x86_64-linux".nix-alien
        ];

        programs.nix-ld.enable = true;
      }
    ];

  meta.name = "nix-alien";
}
