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
        }
      )
    ];

  meta.name = "gnome-control-center";
}
