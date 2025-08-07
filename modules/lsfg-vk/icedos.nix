{ ... }:

{
  options = { };

  inputs.lsfg-vk = {
    url = "github:pabloaul/lsfg-vk-flake";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      inputs.lsfg-vk.nixosModules.default

      {
        services.lsfg-vk = {
          enable = true;
          ui.enable = true;
        };
      }
    ];

  meta = {
    name = "lsfg-vk";
    depends = [ ];
  };
}
