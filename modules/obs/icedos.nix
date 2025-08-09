{ icedosLib, ... }:

{
  options.icedos.applications.obs.virtualCamera = icedosLib.mkBoolOption { default = false; };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:
        {
          programs.obs-studio = {
            enable = true;
            enableVirtualCamera = config.icedos.applications.obs.virtualCamera;
          };
        }
      )
    ];

  meta.name = "obs";
}
