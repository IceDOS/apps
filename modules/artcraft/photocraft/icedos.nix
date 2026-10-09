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
              photocraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.photocraft ];
        }
      )
    ];

  meta.name = "photocraft";
}
