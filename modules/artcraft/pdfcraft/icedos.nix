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
              pdfcraft = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.pdfcraft ];
        }
      )
    ];

  meta.name = "pdfcraft";
}
