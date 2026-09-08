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
          environment.systemPackages = [ pkgs.gnome-control-center ];

          home-manager.sharedModules = [
            {
              xdg.desktopEntries.gnome-control-center = {
                exec = "env XDG_CURRENT_DESKTOP=GNOME gnome-control-center";
                icon = "gnome-control-center";
                name = "Gnome Control Center";
                terminal = false;
                type = "Application";
              };

              dconf.settings."org/gnome/control-center".last-panel = "online-accounts";
            }
          ];

          icedos.system.tips.list = [
            "GNOME Settings is in your app menu for online accounts and system options."
          ];
        }
      )
    ];

  meta.name = "gnome-control-center";
}
