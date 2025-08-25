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
              intermux = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.intermux ];
        }
      )
    ];

  meta.name = "intermux";
}
