{ pkgs, ... }:

let
  rebootBin = pkgs.writeShellScriptBin "icedos-reboot" ''
    exec /run/wrappers/bin/pkexec ${pkgs.systemd}/bin/systemctl reboot -i
  '';

  rebootUefiBin = pkgs.writeShellScriptBin "icedos-reboot-uefi" ''
    exec /run/wrappers/bin/pkexec ${pkgs.systemd}/bin/systemctl reboot --firmware-setup -i
  '';
in
{
  icedos.applications.toolset.commands = [
    {
      command = "reboot";

      script = ''
        case "$1" in
          "")
            systemctl reboot -i || sudo systemctl reboot -i
            ;;
          uefi)
            systemctl reboot --firmware-setup -i || sudo systemctl reboot --firmware-setup -i
            ;;
          *)
            die "unknown arg: $1"
            ;;
        esac
      '';

      help = "reboot ignoring inhibitors and users, uefi supported by appending it as an argument";
    }
  ];

  home-manager.sharedModules = [
    {
      xdg.desktopEntries.icedos-reboot = {
        name = "Reboot";
        genericName = "Restart the system";
        comment = "Reboot the system, ignoring inhibitors and other logged-in users";
        icon = "system-reboot";
        exec = "${rebootBin}/bin/icedos-reboot";
        terminal = false;
        type = "Application";
        categories = [
          "System"
          "Settings"
        ];
        settings.Keywords = "reboot;restart;shutdown;";
      };

      xdg.desktopEntries.icedos-reboot-uefi = {
        name = "Reboot to UEFI";
        genericName = "Restart into firmware setup";
        comment = "Reboot the system into the UEFI firmware setup screen";
        icon = "system-reboot";
        exec = "${rebootUefiBin}/bin/icedos-reboot-uefi";
        terminal = false;
        type = "Application";
        categories = [
          "System"
          "Settings"
        ];
        settings.Keywords = "reboot;restart;uefi;firmware;bios;";
      };
    }
  ];
}
