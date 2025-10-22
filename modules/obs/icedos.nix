{ icedosLib, ... }:

{
  options.icedos.applications.obs = {
    plugins = icedosLib.mkStrListOption { default = [ ]; };
    virtualCamera = icedosLib.mkBoolOption { default = false; };
  };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, icedosLib, ... }:
        {
          programs.obs-studio =
            let
              inherit (icedosLib) pkgMapper;
              obs = config.icedos.applications.obs;
            in
            {
              enable = true;
              enableVirtualCamera = obs.virtualCamera;
              plugins = pkgMapper obs.plugins;
            };
        }
      )
    ];

  meta.name = "obs";
}
