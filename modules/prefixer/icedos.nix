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

          icedos.system.tips.list = [
            "prefixer <APP_ID> run <exe> runs a Windows tool inside a game's Proton folder."
          ];
        }
      )
    ];

  meta.name = "prefixer";
}
