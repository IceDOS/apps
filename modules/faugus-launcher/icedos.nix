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
              faugus-launcher = final.callPackage ./package.nix { }; # https://nixpk.gs/pr-tracker.html?pr=402220
            })
          ];

          environment.systemPackages = [ pkgs.faugus-launcher ];
        }
      )
    ];

  meta.name = "faugus-launcher";
}
