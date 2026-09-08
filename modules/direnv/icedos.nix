{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        programs.direnv.enable = true;

        icedos.system.tips.list = [
          "direnv loads a project folder's tools the moment you open it in a terminal."
        ];
      }
    ];

  meta.name = "direnv";
}
