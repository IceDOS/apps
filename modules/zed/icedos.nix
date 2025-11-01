{
  lib,
  icedosLib,
  ...
}:

{
  options.icedos.applications.zed =
    let
      inherit (lib) mkOption;

      inherit (icedosLib)
        mkBoolOption
        mkNumberOption
        mkStrListOption
        mkStrOption
        ;

      zed = (fromTOML (lib.fileContents ./config.toml)).icedos.applications.zed;
    in
    {
      autosave = mkBoolOption { default = false; };
      extensions = mkStrListOption { default = zed.extensions; };
      extraPackages = mkStrListOption { default = zed.extraPackages; };
      fhs = mkBoolOption { default = zed.fhs; };
      formatOnSave = mkBoolOption { default = false; };
      fontSize = mkNumberOption { default = zed.fontSize; };
      lspSettings = mkOption { default = { }; };

      theme = {
        dark = mkStrOption { default = zed.theme.dark; };
        light = mkStrOption { default = zed.theme.light; };
        mode = mkStrOption { default = zed.theme.mode; };
      };

      vim = mkBoolOption { default = zed.vim; };
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
            mapAttrs
            mkIf
            splitString
            ;

          inherit (pkgs) nil nixd zed-editor-fhs;

          cfg = config.icedos;
          zed = cfg.applications.zed;
          users = cfg.users;

          lsp.nil.initialization_options.formatting.command = [ "nixfmt" ];
          lspSettings = lsp // zed.lspSettings;

          pkgMapper =
            pkgList: lists.map (pkgName: foldl' (acc: cur: acc.${cur}) pkgs (splitString "." pkgName)) pkgList;
        in
        {
          environment.variables.EDITOR = mkIf (
            cfg.applications.defaultEditor == "dev.zed.Zed.desktop"
          ) "zeditor -n -w";

          environment.systemPackages = [
            nil
            nixd
          ];

          home-manager.users = mapAttrs (user: _: {
            programs.zed-editor = {
              enable = true;
              package = mkIf (zed.fhs) zed-editor-fhs;

              extensions = zed.extensions ++ [
                "nix"
                "one-dark-pro"
                "toml"
              ];

              extraPackages = pkgMapper zed.extraPackages;

              userSettings = {
                auto_update = false;
                autosave = if (zed.autosave) then "on" else "off";
                buffer_font_family = "JetBrainsMono Nerd Font";
                buffer_font_size = zed.fontSize;
                collaboration_panel.button = false;
                features.edit_prediction_provider = "none";
                format_on_save = if (zed.formatOnSave) then "on" else "off";

                indent_guides = {
                  enabled = true;
                  coloring = "indent_aware";
                };

                inlay_hints.enabled = true;
                journal.hour_format = "hour24";
                notification_panel.button = false;
                relative_line_numbers = true;
                show_whitespaces = "boundary";
                tabs.git_status = true;

                terminal = {
                  blinking = "on";
                  copy_on_select = true;
                  font_family = "JetBrainsMono Nerd Font";
                  font_size = zed.fontSize;
                };

                theme = {
                  dark = zed.theme.dark;
                  light = zed.theme.light;
                  mode = zed.theme.mode;
                };

                ui_font_size = zed.fontSize + 2;
                vim_mode = zed.vim;

                lsp = lspSettings;
              };
            };
          }) users;
        }
      )
    ];

  meta.name = "zed";
}
