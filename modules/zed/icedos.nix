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

      inherit ((fromTOML (lib.fileContents ./config.toml)).icedos.applications.zed)
        autosave
        extensions
        extraPackages
        fhs
        fontSize
        formatOnSave
        languages
        lsp
        theme
        vim
        ;
    in
    {
      autosave = mkBoolOption { default = autosave; };
      extensions = mkStrListOption { default = extensions; };
      extraPackages = mkStrListOption { default = extraPackages; };
      fhs = mkBoolOption { default = fhs; };
      fontSize = mkNumberOption { default = fontSize; };
      formatOnSave = mkBoolOption { default = formatOnSave; };
      languages = mkOption { default = languages; };
      lsp = mkOption { default = lsp; };

      theme =
        let
          inherit (theme) dark light mode;
        in
        {
          dark = mkStrOption { default = dark; };
          light = mkStrOption { default = light; };
          mode = mkStrOption { default = mode; };
        };

      vim = mkBoolOption { default = vim; };
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
          inherit (config.icedos.applications) defaultEditor zed;

          inherit (zed)
            autosave
            extensions
            extraPackages
            fhs
            fontSize
            formatOnSave
            theme
            languages
            lsp
            vim
            ;

          inherit (lib) mkIf;
          inherit (pkgs) nil nixd zed-editor-fhs;
        in
        {
          environment.variables.EDITOR = mkIf (defaultEditor == "dev.zed.Zed.desktop") "zeditor -n -w";

          environment.systemPackages = [
            nil
            nixd
          ];

          programs.nix-ld.enable = mkIf (!fhs) true;

          home-manager.sharedModules = [
            {
              programs.zed-editor = {
                enable = true;

                extensions = extensions ++ [
                  "nix"
                  "one-dark-pro"
                  "toml"
                ];

                extraPackages = icedosLib.pkgMapper pkgs extraPackages;
                package = mkIf fhs zed-editor-fhs;

                userSettings = lib.mkMerge [
                  {
                    inherit
                      (
                        lsp
                        // {
                          lsp.nil.initialization_options.formatting.command = [ "nixfmt" ];
                        }
                        // {
                          inherit languages;
                        }
                      )
                      lsp
                      languages
                      ;

                    auto_update = false;
                    autosave = if autosave then "on" else "off";
                    collaboration_panel.button = false;
                    format_on_save = if formatOnSave then "on" else "off";

                    indent_guides = {
                      enabled = true;
                      coloring = "indent_aware";
                    };

                    inlay_hints.enabled = true;
                    journal.hour_format = "hour24";
                    notification_panel.button = false;
                    relative_line_numbers = "enabled";
                    show_whitespaces = "boundary";
                    tabs.git_status = true;

                    terminal =
                      let
                        stylixOn = config.stylix.enable or false;
                      in
                      {
                        blinking = "on";
                        copy_on_select = true;
                        font_family = if stylixOn then config.stylix.fonts.monospace.name else "JetBrainsMono Nerd Font";
                        font_size = if stylixOn then (config.stylix.fonts.sizes.terminal or 12) else fontSize;
                      };

                    vim_mode = vim;
                  }

                  (mkIf (!(config.stylix.enable or false)) {
                    buffer_font_family = "JetBrainsMono Nerd Font";
                    buffer_font_size = fontSize;
                    ui_font_size = fontSize + 2;

                    theme =
                      let
                        inherit (theme) dark light mode;
                      in
                      {
                        inherit dark light mode;
                      };
                  })
                ];
              };
            }
          ];
        }
      )
    ];

  meta.name = "zed";
}
