{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      { programs.direnv.enable = true; }
    ];

  meta.name = "direnv";
}
