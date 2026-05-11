{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { icedosLib, ... }:
        {
          imports = icedosLib.getModules ./modules;
        }
      )
    ];

  meta.name = "toolset";
}
