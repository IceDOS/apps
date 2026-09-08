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

          icedos.system.tips.list = [
            "nvim edits text in the terminal; press Escape, then type :q and Enter to quit."
          ];
        }
      )
    ];

  meta.name = "neovim";
}
