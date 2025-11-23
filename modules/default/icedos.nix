{ icedosLib, lib, ... }:

{
  options.icedos.applications =
    let
      inherit (icedosLib) mkStrOption mkStrListOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications)
        defaultBrowser
        defaultEditor
        extraPackages
        insecurePackages
        ;
    in
    {
      defaultBrowser = mkStrOption { default = defaultBrowser; };
      defaultEditor = mkStrOption { default = defaultEditor; };
      extraPackages = mkStrListOption { default = extraPackages; };
      insecurePackages = mkStrListOption { default = insecurePackages; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:

        let
          inherit (lib)
            foldl'
            lists
            splitString
            ;

          cfg = config.icedos;

          pkgMapper =
            pkgList: lists.map (pkgName: foldl' (acc: cur: acc.${cur}) pkgs (splitString "." pkgName)) pkgList;
        in
        {
          environment.systemPackages =
            with pkgs;
            [
              efibootmgr # Edit EFI entries
              killall # Tool to kill all programs matching process name
              ntfs3g # Support NTFS drives
              neovim # CLI text editor
              p7zip # 7zip
              unrar # Support opening rar files
              unzip # An extraction utility
              wget # Terminal downloader
            ]
            ++ (pkgMapper cfg.applications.extraPackages);

          nixpkgs.config.permittedInsecurePackages = cfg.applications.insecurePackages;
          programs.nano.enable = false;
        }
      )
    ];

  meta = {
    name = "default";

    dependencies = [
      {
        modules = [
          "bash"
          "direnv"
          "git"
          "kitty"
          "nh"
          "nix"
          "nix-health"
          "nixfmt"
          "ssh"
          "toolset"
          "zsh"
        ];
      }
    ];
  };
}
