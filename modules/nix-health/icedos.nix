{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          pkgs,
          ...
        }:

        {
          icedos.system.toolset.commands = [
            {
              command = "health";
              script = ''"${pkgs.nix-health}/bin/nix-health" -q "$@"'';
              help = "print information about system state";
            }
          ];

          icedos.system.tips.list = [
            "icedos health checks your system and reports anything that looks wrong."
          ];
        }
      )
    ];

  meta.name = "nix-health";
}
