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
              citron = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = with pkgs; [
            citron
          ];
        }
      )
    ];

  meta.name = "citron";
}
