{ icedosLib, lib, ... }:

{
  options.icedos.applications.steam.os-session =
    let
      inherit (icedosLib) mkBoolOption mkStrOption;
      inherit (defaultConfig) auto-start user;

      defaultConfig =
        let
          inherit (lib) importTOML;
        in
        (importTOML ./config.toml).icedos.applications.steam.os-session;
    in
    {
      auto-start = {
        enable = mkBoolOption { default = auto-start.enable; };
        desktopSession = mkStrOption { default = auto-start.desktopSession; };
      };

      user = mkStrOption { default = user; };
    };

  outputs.nixosModules =
    { inputs, ... }:
    [
      inputs.jovian.nixosModules.default

      (
        {
          config,
          icedosLib,
          lib,
          ...
        }:

        let
          inherit (applications.steam.os-session) auto-start user;
          inherit (config.icedos) applications system;
          inherit (config.services.displayManager) autoLogin;
          inherit (icedosLib) validate;
          inherit (lib) mkIf;
          inherit (system) isFirstBuild;
        in
        mkIf (!isFirstBuild) {
          jovian = {
            hardware.has.amd.gpu = icedosLib.hasModule {
              inherit config;
              url = "github:icedos/hardware";
              name = "radeon";
            };

            steam = {
              inherit user;
              enable = true;

              autoStart =
                auto-start.enable
                && (validate.abort {
                  when = autoLogin.enable;
                  path = "icedos.applications.steam.os-session.auto-start";
                  msg = ''Autologin is enabled for user "${autoLogin.user}" - this configuration is incompatible with steam os session's autostart. Please remove the "icedos.desktop.autologinUser" entry!'';
                });

              desktopSession = auto-start.desktopSession;
              updater.splash =
                if
                  (icedosLib.hasModule {
                    inherit config;
                    url = "github:icedos/hardware";
                    name = "steamdeck";
                  })
                then
                  "jovian"
                else
                  "vendor";
            };
          };
        }
      )
    ];

  meta = {
    name = "steamos-session";

    dependencies = [
      { modules = [ "steam" ]; }

      {
        url = "github:icedos/providers";

        modules = [
          "jovian"
        ];
      }
    ];
  };
}
