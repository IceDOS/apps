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
              eden = final.callPackage ./package.nix {
                inherit (icedosLib.packaging) extractAppImage installDesktopEntry;
              };
            })
          ];

          environment.systemPackages = with pkgs; [
            eden
          ];
        }
      )
    ];

  meta.name = "eden";
}
