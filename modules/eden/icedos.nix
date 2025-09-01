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
              eden = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = with pkgs; [
            eden
          ];
        }
      )
    ];

  meta.name = "eden";
}
