{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          pkgs,
          ...
        }:
        {
          nixpkgs.overlays = [
            (final: super: {
              bb-launcher = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.bb-launcher ];
        }
      )
    ];

  meta.name = "bb-launcher";
}
