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
              materialcraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.materialcraft ];
        }
      )
    ];

  meta.name = "materialcraft";
}
