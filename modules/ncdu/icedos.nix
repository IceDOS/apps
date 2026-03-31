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
                inherit command;
                bin = "${pkgs.writeShellScript command ''${pkgs.ncdu}/bin/ncdu "$@"''}";
                help = "see disk usage on current folder or provided path";
              }
            )
          ];
        }
      )
    ];

  meta.name = "ncdu";
}
