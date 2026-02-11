{ ... }:

{
  inputs.prefixer = {
    url = "github:wojtmic/prefixer";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      (
        { pkgs, ... }:
        {
          environment.systemPackages = [
            inputs.prefixer.packages.${pkgs.stdenv.hostPlatform.system}.default
          ];
        }
      )
    ];

  meta.name = "prefixer";
}
