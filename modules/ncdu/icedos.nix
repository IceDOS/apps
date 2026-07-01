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
              command = "du";
              script = ''${pkgs.ncdu}/bin/ncdu "$@"'';
              help = "see disk usage on current folder or provided path";

              completion.files = true;
            }
          ];
        }
      )
    ];

  meta.name = "ncdu";
}
