{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          nixpkgs.overlays = [
            (final: super: {
              winboat = final.callPackage ./package.nix { };
            })
          ];

          boot.kernelModules = [
            "ip_tables"
            "iptable_nat"
          ];

          environment.systemPackages = with pkgs; [
            freerdp
            winboat
          ];

          virtualisation.docker.enable = true;

          users.users = lib.mapAttrs (user: _: {
            extraGroups = [ "docker" ];
          }) config.icedos.users;
        }
      )
    ];

  meta.name = "winboat";
}
