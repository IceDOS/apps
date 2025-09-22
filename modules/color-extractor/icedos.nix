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
              color-extractor = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = with pkgs; [
            color-extractor
          ];
        }
      )
    ];

  meta.name = "color-extractor";
}
