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
          environment.systemPackages = with pkgs; [
            efibootmgr # Edit EFI entries
            killall # Tool to kill all programs matching process name
            ntfs3g # Support NTFS drives
            p7zip # 7zip
            unrar # Support opening rar files
            unzip # An extraction utility
            wget # Terminal downloader
          ];

          programs.nano.enable = false;
        }
      )
    ];

  meta = {
    name = "default";

    dependencies = [
      {
        modules = [
          "direnv"
          "nix-health"
          "toolset"
        ];
      }
    ];

    optionalDependencies = [
      {
        modules = [
          "kitty"
          "neovim"
        ];
      }
    ];
  };
}
