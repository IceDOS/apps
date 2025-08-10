{ icedosLib, ... }:

{
  options.icedos.applications.sunshine.autoStart = icedosLib.mkBoolOption { default = false; };

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
