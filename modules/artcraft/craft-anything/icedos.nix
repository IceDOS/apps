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
              craft-anything = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.craft-anything ];
        }
      )
    ];

  meta.name = "craft-anything";
}
