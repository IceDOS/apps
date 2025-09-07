{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          ...
        }:

        {
          boot = {
            kernelModules = [ "zenergy" ];
            extraModulePackages = with config.boot.kernelPackages; [ zenergy ];
          };
        }
      )
    ];

  meta.name = "zenergy";
}
