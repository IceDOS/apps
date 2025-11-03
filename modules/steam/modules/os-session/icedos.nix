{ icedosLib, lib, ... }:

{
  options.icedos.applications.steam.os-session =
    let
      inherit (icedosLib) mkBoolOption mkStrOption;
      inherit (defaultConfig) autoStart user;

      defaultConfig =
        let
          inherit (lib) readFile;
        in
        (fromTOML (readFile ./config.toml)).icedos.applications.steam.os-session;
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
          inherit (applications.steam.os-session) autoStart user;
          inherit (config.icedos) applications hardware system;
          inherit (config.services.displayManager) autoLogin;
          inherit (hardware) devices graphics;
          inherit (icedosLib) abortIf;
          inherit (lib) hasAttr mkIf;
          inherit (system) isFirstBuild;
        in
        mkIf (!isFirstBuild) {
          jovian = {
            hardware.has.amd.gpu = hasAttr "radeon" graphics;

            steam = {
              inherit user;
              enable = true;

              autoStart =
                autoStart.enable
                && (
                  let
                    inherit (autoLogin) enable user;
                  in
                  abortIf enable ''Autologin is enabled for user "${user}" - this configuration is incompatible with steam os session's autostart. Please remove the "icedos.desktop.autologinUser" entry!''
                );

              desktopSession = autoStart.desktopSession;
              updater.splash = if (hasAttr "steamdeck" devices) then "jovian" else "vendor";
            };
          };
        }
      )
    ];

  meta = {
    name = "steamos-session";

    dependencies = [
      {
        url = "github:icedos/providers";

        modules = [
          "jovian"
        ];
      }
    ];
  };
}
