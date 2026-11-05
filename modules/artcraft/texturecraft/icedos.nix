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
              texturecraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.texturecraft ];
        }
      )
    ];

  meta.name = "texturecraft";
}
