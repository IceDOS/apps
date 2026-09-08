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

          icedos.system.tips.list = [
            "NX Optimizer adds smoother framerates and camera control to Switch games like Zelda."
          ];
        }
      )
    ];

  meta.name = "nx-optimizer";
}
