{ icedosLib, lib, ... }:

{
  options.icedos.applications.nh.gc =
    let
      inherit (icedosLib) mkBoolOption mkNumberOption mkStrOption;
      gc = (fromTOML (lib.fileContents ./config.toml)).icedos.applications.nh.gc;
    in
    {
      automatic = mkBoolOption { default = gc.automatic; };
      days = mkNumberOption { default = gc.days; };
      generations = mkNumberOption { default = gc.generations; };
      interval = mkStrOption { default = gc.interval; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          pkgs,
          ...
        }:

        let
          cfg = config.icedos.applications.nh.gc;
          command = "gc";
          days = "${toString (cfg.days)}d";
          generations = toString (cfg.generations);
        in
        {
          icedos.applications.toolset.commands = [
            {
              bin = "${pkgs.writeShellScript command ''"${pkgs.nh}/bin/nh" clean all -k "${generations}" -K "${days}"''}";
              command = command;
              help = "clean nix plus home manager, store and profiles";
            }
          ];

          programs.nh = {
            enable = true;

            clean = {
              enable = cfg.automatic;
              extraArgs = "-k ${toString (cfg.generations)} -K ${days}";
              dates = cfg.interval;
            };
          };
        }
      )
    ];

  meta.name = "nh";
}
