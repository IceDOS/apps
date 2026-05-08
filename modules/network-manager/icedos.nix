{ icedosLib, lib, ... }:

{
  options.icedos.applications.network-manager.applet =
    let
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.network-manager)
        applet
        ;
    in
    icedosLib.mkBoolOption { default = applet; };

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
          inherit (lib) mkIf;
          inherit (icedosLib.users) mkGroupInjector;
          inherit (config.icedos) applications users;
          inherit (applications.network-manager) applet;
        in

        {
          networking.networkmanager.enable = true;

          users.users = mkGroupInjector "networkmanager" users;

          home-manager.sharedModules = [
            {
              xdg.desktopEntries = mkIf applet {
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
            }
          ];
        }
      )
    ];

  meta.name = "network-manager";
}
