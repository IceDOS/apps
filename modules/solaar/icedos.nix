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

          icedos.system.tips.list = [
            "Solaar pairs and configures Logitech wireless mice and keyboards."
          ];
        }
      )
    ];

  meta.name = "solaar";
}
