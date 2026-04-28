{ icedosLib, lib, ... }:

{
  options.icedos.applications.sunshine.autoStart =
    let
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.sunshine)
        autoStart
        ;
    in
    icedosLib.mkBoolOption { default = autoStart; };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:

        {
          services.sunshine = {
            enable = true;
            capSysAdmin = true;
            autoStart = config.icedos.applications.sunshine.autoStart;
          };
        }
      )
    ];

  meta.name = "sunshine";
}
