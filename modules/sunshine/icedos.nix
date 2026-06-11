{ icedosLib, lib, ... }:

{
  options.icedos.applications.sunshine =
    let
      inherit (icedosLib) mkAttrsOption mkBoolOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.sunshine)
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
        }
      )
    ];

  meta.name = "sunshine";
}
