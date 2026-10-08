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
              bbhost = final.callPackage ./package.nix {
                inherit (icedosLib.packaging) installDesktopEntry;
              };
            })
          ];

          environment.systemPackages = [ pkgs.bbhost ];
        }
      )
    ];

  meta.name = "bbhost";
}
