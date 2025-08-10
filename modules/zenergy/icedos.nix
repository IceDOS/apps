{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          ...
        }:

        {
          boot = {
            kernelModules = [ "zenergy" ];

            extraModulePackages =
              with config.boot.kernelPackages;
              if (lib.versionAtLeast kernel.version "6.16") then
                [
                  (zenergy.overrideAttrs (super: {
                    patches = (super.patches or [ ]) ++ [ ./patch.diff ];
                  }))
                ]
              else
                [ zenergy ];
          };
        }
      )
    ];

  meta.name = "zenergy";
}
