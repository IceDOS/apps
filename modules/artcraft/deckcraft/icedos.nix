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
              deckcraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.deckcraft ];
        }
      )
    ];

  meta.name = "deckcraft";
}
