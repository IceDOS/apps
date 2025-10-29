{ icedosLib, lib, ... }:

{
  options.icedos.applications.steam.session =
    let
      inherit (icedosLib) mkBoolOption mkStrOption;
      inherit (defaultConfig) autoStart user;

      defaultConfig =
        let
          inherit (lib) readFile;
        in
        (fromTOML (readFile ./config.toml)).icedos.applications.steam.session;
    in
    {
      autoStart = {
        enable = mkBoolOption { default = autoStart.enable; };
        desktopSession = mkStrOption { default = autoStart.desktopSession; };
      };

      user = mkStrOption { default = user; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          icedosLib,
          lib,
          ...
        }:

        let
          inherit (icedosLib) abortIf;
          inherit (lib) hasAttr mkIf;
          inherit (config.services.displayManager) autoLogin;
          inherit (config.icedos) applications hardware system;
          inherit (applications.steam.session) autoStart user;
        in
        mkIf (!system.isFirstBuild) {
          jovian = {
            hardware.has.amd.gpu = hasAttr "radeon" hardware.graphics;

            steam = {
              inherit user;
              enable = true;

              autoStart =
                autoStart.enable
                && (abortIf (autoLogin.enable) ''Autologin is enabled for user "${autoLogin.user}" - this configuration is incompatible with steam session's autostart. Please remove the "icedos.desktop.autologinUser" entry!'');

              desktopSession = autoStart.desktopSession;
              updater.splash = if (hasAttr "steamdeck" hardware.devices) then "jovian" else "vendor";
            };
          };
        }
      )
    ];

  meta.name = "steam-session";
}
