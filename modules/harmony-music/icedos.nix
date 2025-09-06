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
              harmony-music = final.callPackage ./package.nix { };
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
