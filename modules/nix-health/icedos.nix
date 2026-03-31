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
                inherit command;
                bin = "${pkgs.writeShellScript command ''"${pkgs.nix-health}/bin/nix-health" -q "$@"''}";
                help = "print information about system state";
              }
            )
          ];
        }
      )
    ];

  meta.name = "nix-health";
}
