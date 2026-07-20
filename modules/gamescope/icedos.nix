{ lib, icedosLib, ... }:

{
  options.icedos.applications.gamescope =
    let
      inherit ((fromTOML (lib.readFile ./config.toml)).icedos.applications.gamescope) capSysNice wsi;
    in
    {
      capSysNice = icedosLib.mkBoolOption { default = capSysNice; };
      wsi = icedosLib.mkBoolOption { default = wsi; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          ...
        }:

        {
          programs.gamescope = {
            enable = true;
            capSysNice = config.icedos.applications.gamescope.capSysNice;
            enableWsi = config.icedos.applications.gamescope.wsi;
          };
        }
      )
    ];

  meta.name = "gamescope";
}
