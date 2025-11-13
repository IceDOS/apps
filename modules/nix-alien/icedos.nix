{ ... }:

{
  inputs.nix-alien = {
    url = "github:thiagokokada/nix-alien";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      (
        { pkgs, ... }:
        {
          environment.systemPackages = [
            inputs.nix-alien.packages.${pkgs.stdenv.system}.nix-alien
          ];

          programs.nix-ld.enable = true;
        }
      )
    ];

  meta.name = "nix-alien";
}
