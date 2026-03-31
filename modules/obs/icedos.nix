{ icedosLib, lib, ... }:

{
  options.icedos.applications.obs =
    let
      inherit (icedosLib) mkBoolOption mkStrListOption;

      inherit ((fromTOML (lib.readFile ./config.toml)).icedos.applications.obs)
        plugins
        virtualCamera
        ;
    in
    {
      plugins = mkStrListOption { default = plugins; };
      virtualCamera = mkBoolOption { default = virtualCamera; };
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
