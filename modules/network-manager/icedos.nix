{ icedosLib, ... }:

{
  options.icedos.applications.network-manager.applet = icedosLib.mkBoolOption { default = false; };

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

        let
          inherit (lib) mapAttrs mkIf;
          cfg = config.icedos;
        in

        {
          networking = {
            networkmanager.enable = true;
            firewall.enable = false;
          };

          users.users = mapAttrs (user: _: { extraGroups = [ "networkmanager" ]; }) cfg.users;

          home-manager.users = mapAttrs (user: _: {
            xdg.desktopEntries = mkIf (cfg.applications.network-manager.applet) {
              nm-connection-editor = {
                exec = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
                icon = "epiphany";
                name = "Network Connection Editor";
                terminal = false;
                type = "Application";
              };

              nm-tray = {
                exec = "${pkgs.networkmanagerapplet}/bin/nm-applet";
                icon = "epiphany";
                name = "Network Connection Tray";
                terminal = false;
                type = "Application";
              };
            };
          }) cfg.users;
        }
      )
    ];

  meta.name = "network-manager";
}
