{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    filter
    imap0
    listToAttrs
    map
    mapAttrs
    mkIf
    ;

  cfg = config.icedos;
  zen = cfg.applications.zen;
  pwaProfiles = filter (profile: profile.pwa) zen.profiles;
  stylixOn = config.stylix.enable or false;
in
{
  environment.systemPackages = map (
    profile:
    pkgs.writeShellScriptBin profile.exec ''
      zen-beta --no-remote -P ${profile.exec} --name "${profile.exec}" ${toString profile.sites}
    ''
  ) pwaProfiles;

  home-manager.users = mapAttrs (_: _: {
    xdg.desktopEntries = listToAttrs (
      map (profile: {
        name = profile.exec;

        value = {
          exec = profile.exec;
          icon = profile.icon;
          name = profile.name;
          terminal = false;
          type = "Application";
        };
      }) pwaProfiles
    );

    programs.zen-browser.profiles = listToAttrs (
      imap0 (i: profile: {
        name = profile.exec;
        value = {
          id = i;
          name = profile.exec;
          path = profile.exec;
          isDefault = profile.default;
        };
      }) zen.profiles
    );

    stylix.targets.zen-browser.profileNames = mkIf stylixOn (map (p: p.exec) zen.profiles);
  }) cfg.users;
}
