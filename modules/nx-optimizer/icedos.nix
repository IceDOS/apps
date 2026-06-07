{ icedosLib, ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        {
          nixpkgs.overlays = [
            (final: super: {
              nx-optimizer = final.callPackage ./package.nix {
                inherit (icedosLib.packaging) installDesktopEntry;
              };
            })
          ];

          environment.systemPackages = with pkgs; [
            nx-optimizer
          ];
        }
      )
    ];

  meta.name = "nx-optimizer";
}
