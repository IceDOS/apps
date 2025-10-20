{ icedosLib, ... }:

{
  options.icedos.applications.scx = {
    extraArgs = icedosLib.mkStrListOption { default = [ ]; };
    scheduler = icedosLib.mkStrOption { default = "lavd"; };
  };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:
        {
          services.scx =
            let
              scx = config.icedos.applications.scx;
            in
            {
              enable = true;
              extraArgs = scx.extraArgs;
              scheduler = "scx_${scx.scheduler}";
            };
        }
      )
    ];

  meta.name = "scx";
}
