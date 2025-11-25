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
              reigntweak = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages =
            let
              inherit (pkgs) reigntweak;
            in
            [
              reigntweak
            ];
        }
      )
    ];

  meta.name = "reigntweak";
}
