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
            inputs.nix-alien.packages.${pkgs.stdenv.hostPlatform.system}.nix-alien
          ];

          programs.nix-ld.enable = true;

          icedos.system.tips.list = [
            "nix-alien runs downloaded Linux programs that were never built for NixOS."
          ];
        }
      )
    ];

  meta.name = "nix-alien";
}
