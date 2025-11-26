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
          environment.systemPackages = [ pkgs.neovim ];
        }
      )
    ];

  meta.name = "neovim";
}
