{ icedosLib, ... }:

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
              citron = final.callPackage ./package.nix {
                inherit (icedosLib.packaging) extractAppImage installDesktopEntry;
              };
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
