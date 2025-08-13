{ icedosLib, ... }:

{
  options.icedos.applications.steam.session =
    let
      inherit (icedosLib) mkBoolOption mkStrOption;
    in
    {
      autoStart = {
        enable = mkBoolOption { default = false; };
        desktopSession = mkStrOption { default = ""; };
      };

      user = mkStrOption { default = ""; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          ...
        }:

        let
          inherit (lib) hasAttr mkIf;
          cfg = config.icedos;
          session = cfg.applications.steam.session;
        in
        {
          jovian = mkIf (!cfg.system.isFirstBuild) {
            hardware.has.amd.gpu = hasAttr "radeon" cfg.hardware.graphics;

            steam = {
              enable = true;
              autoStart = session.autoStart.enable;
              desktopSession = session.autoStart.desktopSession;
              updater.splash = if (hasAttr "steamdeck" cfg.hardware.devices) then "jovian" else "vendor";
              user = session.user;
            };
          };
        }
      )
    ];

  meta.name = "steam-session";
}
