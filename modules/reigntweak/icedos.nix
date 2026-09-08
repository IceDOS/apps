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

          icedos.system.tips.list = [
            "reigntweak unlocks the framerate and ultrawide support in Elden Ring Nightreign."
          ];
        }
      )
    ];

  meta.name = "reigntweak";
}
