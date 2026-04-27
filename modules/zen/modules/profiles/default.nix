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
    optionalAttrs
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

  home-manager.users = mapAttrs (
    _: _:
    {
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
    }
    # See librewolf module for why this uses `optionalAttrs` rather than `mkIf`:
    # the `stylix.targets.<x>.profileNames` option only exists on each
    # home-manager user when stylix's home-manager module is imported, which
    # happens when `stylix.enable = true`. With mkIf, the path would be
    # registered as a definition even with a false condition and fail.
    // optionalAttrs stylixOn {
      stylix.targets.zen-browser.profileNames = map (p: p.exec) zen.profiles;
    }
  ) cfg.users;
}
