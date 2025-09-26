{ ... }:

{
  inputs.ambiled = {
    url = "github:jim3692/ambiled";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      {
        environment.systemPackages = [
          inputs.ambiled.packages."x86_64-linux".default
        ];
      }
    ];

  meta.name = "ambiled";
}
