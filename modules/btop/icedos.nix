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

        let
          inherit (lib) mkIf;

          btop-sudo = pkgs.writeShellScriptBin "btop-sudo" ''
            CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/btop"
            exec /run/wrappers/bin/pkexec ${pkgs.btop}/bin/btop \
              -c "$CONFIG_DIR/btop.conf" \
              --themes-dir "$CONFIG_DIR/themes" \
              "$@"
          '';
        in
        {
          home-manager.sharedModules = [
            {
              programs.btop.enable = true;

              xdg.configFile."btop/btop.conf" = mkIf (!(config.stylix.enable or false)) {
                source = ./btop.conf;
                force = true;
              };

              xdg.desktopEntries.btop-sudo = {
                name = "sudo btop++";
                genericName = "System Monitor";
                comment = "Resource monitor that shows usage and stats for processor, memory, disks, network and processes";
                icon = "btop";
                exec = "${btop-sudo}/bin/btop-sudo";
                terminal = true;
                type = "Application";

                categories = [
                  "System"
                  "Monitor"
                  "ConsoleOnly"
                ];

                settings.Keywords = "system;process;task;root;sudo";
              };
            }
          ];
        }
      )
    ];

  meta.name = "btop";
}
