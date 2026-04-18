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
          icedos.applications.toolset.commands = [
            {
              command = "health";
              script = ''"${pkgs.nix-health}/bin/nix-health" -q "$@"'';
              help = "print information about system state";
            }
          ];
        }
      )
    ];

  meta.name = "nix-health";
}
