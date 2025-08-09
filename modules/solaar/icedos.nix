{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        {
          environment.systemPackages = [ pkgs.solaar ];
          services.udev.packages = [ pkgs.logitech-udev-rules ];
        }
      )
    ];

  meta.name = "solaar";
}
