{ ... }:

{
  inputs.ambiled = {
    url = "github:jim3692/ambiled";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      (
        { pkgs, ... }:
        {
          environment.systemPackages = [
            inputs.ambiled.packages.${pkgs.stdenv.hostPlatform.system}.default
          ];
        }
      )
    ];

  meta.name = "ambiled";
}
