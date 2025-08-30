{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        {
          environment.systemPackages = [ pkgs.distrobox ];
          virtualisation.podman.enable = true;
        }
      )
    ];

  meta.name = "podman";
}
