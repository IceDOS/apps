{ pkgs, ... }:

let
  logoutBin = pkgs.writeShellScriptBin "icedos-logout" ''
    ${pkgs.zenity}/bin/zenity \
      --question \
      --title="Logout" \
      --text="Logout from this session?\n\nAll running processes of user $USER, will be forcibly terminated." \
      --ok-label="Logout" \
      --cancel-label="Cancel" \
      && exec ${pkgs.procps}/bin/pkill -KILL -u "$USER"
  '';
in
{
  icedos.applications.toolset.commands = [
    {
      command = "logout";
      script = "pkill -KILL -u $USER";
      help = "force kill all current user processes, resulting in a logout";
    }
  ];

  home-manager.sharedModules = [
    {
      xdg.desktopEntries.icedos-logout = {
        name = "Force Logout";
        comment = "Force-terminate all processes for the current user";
        icon = "system-log-out";
        exec = "${logoutBin}/bin/icedos-logout";
        terminal = false;
        type = "Application";
        categories = [ "System" ];
      };
    }
  ];
}
