{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    optional
    optionalAttrs
    types
    ;
in
{
  options = {
    icedos.applications.lsfg-vk = mkOption { type = types.bool; };
  };

  inputs = optionalAttrs config.applications.lsfg-vk {
    lsfg-vk = {
      url = "github:pabloaul/lsfg-vk-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixosModules =
      { inputs, ... }:
      optional config.applications.lsfg-vk [
        inputs.lsfg-vk.nixosModules.default
        ./.
      ];
  };

  meta = {
    name = "lsfg-vk";
    depends = [
      {
        modules = [ "chaotic" ];
      }
    ];
  };
}
