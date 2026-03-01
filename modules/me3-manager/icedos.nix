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
              me3-manager = final.callPackage ./package.nix { me3 = pkgs.me3; };
            })
          ];

          environment.systemPackages = with pkgs; [
            me3-manager
          ];
        }
      )
    ];

  meta = {
    dependencies = [ { modules = [ "me3" ]; } ];
    name = "me3-manager";
  };
}
