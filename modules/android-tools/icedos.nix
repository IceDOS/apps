{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:

        let
          inherit (lib) mapAttrs;
          cfg = config.icedos;
        in
        {
          environment.systemPackages = [ pkgs.scrcpy ];
          programs.adb.enable = true;

          users.users = mapAttrs (user: _: {
            extraGroups = [ "adbusers" ];
          }) cfg.users;
        }
      )
    ];

  meta.name = "android-tools";
}
