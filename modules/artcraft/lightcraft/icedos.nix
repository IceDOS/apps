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
              lightcraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.lightcraft ];
        }
      )
    ];

  meta.name = "lightcraft";
}
