{ icedosLib, lib, ... }:

{
  options.icedos.applications.zenstates.serviceArgs =
    let
      inherit (lib) readFile;
      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.zenstates) serviceArgs;
    in
    icedosLib.mkStrOption { default = serviceArgs; };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          pkgs,
          ...
        }:

        {
          environment.systemPackages = [
            pkgs.zenstates
          ];

          systemd.services.zenstates = {
            enable = true;
            description = "Ryzen Undervolt";
            after = [
              "syslog.target"
              "systemd-modules-load.service"
            ];

            unitConfig = {
              ConditionPathExists = "${pkgs.zenstates}/bin/zenstates";
            };

            serviceConfig = {
              User = "root";
              ExecStart = "${pkgs.zenstates}/bin/zenstates ${config.icedos.applications.zenstates.serviceArgs}";
            };

            wantedBy = [ "multi-user.target" ];
          };
        }
      )
    ];

  meta.name = "zenstates";
}
