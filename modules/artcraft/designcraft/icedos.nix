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
              designcraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.designcraft ];
        }
      )
    ];

  meta.name = "designcraft";
}
