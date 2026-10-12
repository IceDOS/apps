{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        {
          nixpkgs.overlays = [
            (final: super: {
              gridcraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.gridcraft ];
        }
      )
    ];

  meta.name = "gridcraft";
}
