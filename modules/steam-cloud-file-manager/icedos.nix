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
              steam-cloud-file-manager = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.steam-cloud-file-manager ];
        }
      )
    ];

  meta.name = "steam-cloud-file-manager";
}
