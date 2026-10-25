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
              figcraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.figcraft ];
        }
      )
    ];

  meta.name = "figcraft";
}
