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
              cadcraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.cadcraft ];
        }
      )
    ];

  meta.name = "cadcraft";
}
