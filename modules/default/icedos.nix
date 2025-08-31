{ icedosLib, ... }:

{
  options.icedos.applications =
    let
      inherit (icedosLib) mkStrOption mkStrListOption;
    in
    {
      defaultBrowser = mkStrOption { default = ""; };
      defaultEditor = mkStrOption { default = ""; };
      extraPackages = mkStrListOption { default = [ ]; };
      insecurePackages = mkStrListOption { default = [ ]; };
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
        }
      )
    ];

  meta.name = "default";
}
