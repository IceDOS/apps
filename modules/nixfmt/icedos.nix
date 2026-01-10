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
            (
              let
                command = "nixf";
              in
              {
                bin = "${pkgs.writeShellScript command ''find "''${1:-.}" -type f -name "*.nix" -exec "${package}/bin/nixfmt" {} \;''}";
                command = command;
                help = "format all nix files of current or provided directory";
              }
            )
          ];
        }
      )
    ];

  meta.name = "nixfmt";
}
