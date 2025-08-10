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
            (
              let
                command = "health";
              in
              {
                bin = "${pkgs.writeShellScript command ''"${pkgs.nix-health}/bin/nix-health" -q "$@"''}";

                command = command;
                help = "print information about system state";
              }
            )
          ];
        }
      )
    ];

  meta.name = "nix-health";
}
