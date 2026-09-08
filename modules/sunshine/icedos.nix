{ icedosLib, lib, ... }:

{
  options.icedos.applications.sunshine =
    let
      inherit (icedosLib) mkAttrsOption mkBoolOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.applications.sunshine)
        applications
        autoStart
        capSysAdmin
        openFirewall
        settings
        ;
    in
    {
      applications = mkAttrsOption { default = applications; };
      autoStart = mkBoolOption { default = autoStart; };
      capSysAdmin = mkBoolOption { default = capSysAdmin; };
      openFirewall = mkBoolOption { default = openFirewall; };
      settings = mkAttrsOption { default = settings; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:

        let
          inherit (config.icedos.applications.sunshine)
            applications
            autoStart
            capSysAdmin
            openFirewall
            settings
            ;
        in
        {
          services.sunshine = {
            enable = true;

            inherit
              applications
              autoStart
              capSysAdmin
              openFirewall
              settings
              ;
          };

          icedos.system.tips.list =
            lib.optionals openFirewall [
              "Sunshine is reachable from the other devices on your network."
            ]
            ++ lib.optionals autoStart [
              "Sunshine starts with your session, so streaming is ready whenever you are."
            ];
        }
      )
    ];

  meta.name = "sunshine";
}
