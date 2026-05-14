{ icedosLib, lib, ... }:

{
  options.icedos.applications.scx =
    let
      inherit (lib) readFile;
      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.scx) extraArgs scheduler;
    in
    {
      extraArgs = icedosLib.mkStrListOption { default = extraArgs; };
      scheduler = icedosLib.mkStrOption { default = scheduler; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          pkgs,
          ...
        }:

        let
          inherit (config.icedos.applications) scx;
          inherit (scx) scheduler;
        in
        {
          services.scx = {
            package = pkgs.scx.full;
            enable = true;
            scheduler = "scx_${scheduler}";
          };
        }
      )
    ];

  meta.name = "scx";
}
