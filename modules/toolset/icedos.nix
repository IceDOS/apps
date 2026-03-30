{ icedosLib, lib, ... }:

{
  options.icedos.applications.toolset.commands =
    let
      inherit (icedosLib) mkSubmoduleListOption mkStrOption;
      inherit ((fromTOML (lib.fileContents ./config.toml)).icedos.applications.toolset) commands;
    in
    mkSubmoduleListOption { default = commands; } {
      bin = mkStrOption { };
      command = mkStrOption { };
      help = mkStrOption { };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          lib,
          ...
        }:

        let
          inherit (lib)
            attrNames
            filterAttrs
            ;

          getModules =
            path:
            map (dir: ./. + ("/modules/" + dir)) (
              attrNames (filterAttrs (_: v: v == "directory") (builtins.readDir path))
            );
        in
        {
          imports = getModules ./modules;
        }
      )
    ];

  meta.name = "toolset";
}
