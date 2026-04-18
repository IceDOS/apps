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

        let
          package = pkgs.nixfmt;
        in
        {
          environment.systemPackages = [ package ];

          icedos.applications.toolset.commands = [
            {
              command = "nixf";
              script = ''find "''${1:-.}" -type f -name "*.nix" -exec "${package}/bin/nixfmt" {} \;'';
              help = "format all nix files of current or provided directory";
            }
          ];
        }
      )
    ];

  meta.name = "nixfmt";
}
