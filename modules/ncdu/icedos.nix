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
              command = "du";
              script = ''${pkgs.ncdu}/bin/ncdu "$@"'';
              help = "see disk usage on current folder or provided path";
            }
          ];
        }
      )
    ];

  meta.name = "ncdu";
}
