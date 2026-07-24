{ icedosLib, lib, ... }:

{
  options.icedos.applications.obs =
    let
      inherit (lib) importTOML;
      inherit (icedosLib) mkBoolOption mkStrListOption;

      inherit ((importTOML ./config.toml).icedos.applications.obs)
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
              inherit (config.icedos.applications) obs;
              inherit (obs) plugins virtualCamera;
            in
            {
              enable = true;
              enableVirtualCamera = virtualCamera;
              plugins = mapper pkgs plugins;
            };
        }
      )
    ];

  meta.name = "obs";
}
