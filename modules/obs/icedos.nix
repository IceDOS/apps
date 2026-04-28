{ icedosLib, lib, ... }:

{
  options.icedos.applications.obs =
    let
      inherit (lib) readFile;
      inherit (icedosLib) mkBoolOption mkStrListOption;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.obs)
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
        {
          config,
          icedosLib,
          pkgs,
          ...
        }:

        {
          programs.obs-studio =
            let
              inherit (icedosLib.pkgs) mapper;
              obs = config.icedos.applications.obs;
            in
            {
              enable = true;
              enableVirtualCamera = obs.virtualCamera;
              plugins = mapper pkgs obs.plugins;
            };
        }
      )
    ];

  meta.name = "obs";
}
