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
              vectorcraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.vectorcraft ];
        }
      )
    ];

  meta.name = "vectorcraft";
}
