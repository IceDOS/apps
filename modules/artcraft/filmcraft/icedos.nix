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
              filmcraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.filmcraft ];
        }
      )
    ];

  meta.name = "filmcraft";
}
