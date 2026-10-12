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
              soundcraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.soundcraft ];
        }
      )
    ];

  meta.name = "soundcraft";
}
