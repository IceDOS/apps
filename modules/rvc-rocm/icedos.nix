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
              rvc-rocm = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = with pkgs; [
            rvc-rocm
          ];

          programs.nix-ld.enable = true;
        }
      )
    ];

  meta.name = "rvc-rocm";
}
