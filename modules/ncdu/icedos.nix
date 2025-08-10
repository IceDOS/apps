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
                command = "du";
              in
              {
                bin = "${pkgs.writeShellScript command ''${pkgs.ncdu}/bin/ncdu "$@"''}";
                command = command;
                help = "see disk usage on current folder or provided path";
              }
            )
          ];
        }
      )
    ];

  meta.name = "ncdu";
}
