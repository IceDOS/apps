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
              wordcraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.wordcraft ];
        }
      )
    ];

  meta.name = "wordcraft";
}
