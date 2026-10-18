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
              simpmusic = final.callPackage ./package.nix {
                inherit (icedosLib.packaging) extractAppImage installDesktopEntry;
              };
            })
          ];

          environment.systemPackages = with pkgs; [
            simpmusic
          ];
        }
      )
    ];

  meta.name = "simpmusic";
}
