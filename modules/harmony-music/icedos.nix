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
              harmony-music = final.callPackage ./package.nix {
                inherit (icedosLib.packaging) installDesktopEntry;
              };
            })
          ];

          environment.systemPackages = with pkgs; [
            harmony-music
          ];
        }
      )
    ];

  meta.name = "harmony-music";
}
