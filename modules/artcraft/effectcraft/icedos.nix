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
              effectcraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.effectcraft ];
        }
      )
    ];

  meta.name = "effectcraft";
}
