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

          icedos.system.tips.list = [
            "icedos du shows which folders are eating your disk space."
          ];
        }
      )
    ];

  meta.name = "ncdu";
}
