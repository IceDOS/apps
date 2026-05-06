{ icedosLib, lib, ... }:

{
  options.icedos.applications.btop =
    let
      inherit (lib) readFile;
      inherit (icedosLib) mkBoolOption mkStrListOption;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.btop)
        speedInBytes
        diskExclusions
        sudoDesktopEntry
        ;
    in
    {
      diskExclusions = mkStrListOption { default = diskExclusions; };
      speedInBytes = mkBoolOption { default = speedInBytes; };
      sudoDesktopEntry = mkBoolOption { default = sudoDesktopEntry; };
    };

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
          inherit (config.icedos.applications.btop) speedInBytes diskExclusions sudoDesktopEntry;
          inherit (lib) concatStringsSep mkIf mkMerge;

          btopBin = pkgs.writeShellScriptBin "btop" ''
            export PATH="${pkgs.coreutils}/bin:${pkgs.glibc.bin}/bin:''${PATH:-}"
            if [ "$(id -u)" -eq 0 ]; then
              if [ -n "''${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
                TARGET_USER=$SUDO_USER
              elif [ -n "''${PKEXEC_UID:-}" ]; then
                TARGET_USER=$(getent passwd "$PKEXEC_UID" | cut -d: -f1)
              else
                TARGET_USER=root
              fi
              TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
              CONFIG_DIR="$TARGET_HOME/.config/btop"
            else
              CONFIG_DIR="''${XDG_CONFIG_HOME:-''${HOME:-/nonexistent}/.config}/btop"
            fi
            if [ -f "$CONFIG_DIR/btop.conf" ]; then
              exec ${pkgs.btop}/bin/btop \
                -c "$CONFIG_DIR/btop.conf" \
                --themes-dir "$CONFIG_DIR/themes" \
                "$@"
            fi
            exec ${pkgs.btop}/bin/btop "$@"
          '';

          btopWrapped = pkgs.symlinkJoin {
            name = "btop-${pkgs.btop.version}";
            paths = [ pkgs.btop ];
            postBuild = ''
              rm $out/bin/btop
              ln -s ${btopBin}/bin/btop $out/bin/btop
            '';
          };

          btop-sudo = pkgs.writeShellScriptBin "btop-sudo" ''
            exec /run/wrappers/bin/pkexec ${btopWrapped}/bin/btop "$@"
          '';
        in
        {
          environment.systemPackages = [ btopWrapped ];

          home-manager.sharedModules = [
            {
              programs.btop = {
                enable = true;
                package = btopWrapped;

                settings = mkMerge [
                  {
                    base_10_sizes = speedInBytes;
                    disk_free_priv = false;
                    swap_disk = false;
                  }

                  (mkIf (diskExclusions != [ ]) {
                    disks_filter = "exclude=" + concatStringsSep " " diskExclusions;
                  })

                  (mkIf (!(config.stylix.enable or false)) {
                    color_theme = "onedark";
                  })
                ];
              };

              xdg.desktopEntries.btop-sudo = mkIf sudoDesktopEntry {
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
