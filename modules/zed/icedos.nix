{
  lib,
  icedosLib,
  ...
}:

{
  options.icedos.applications.zed =
    let
      inherit (lib) readFile;

      inherit (icedosLib)
        mkAttrsOption
        mkBoolOption
        mkNumberOption
        mkStrListOption
        mkStrOption
        ;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.zed)
        autosave
        extensions
        extraPackages
        fhs
        font
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

      font =
        let
          inherit (font) name size;
        in
        {
          name = mkStrOption { default = name; };
          size = mkNumberOption { default = size; };
        };

      formatOnSave = mkBoolOption { default = formatOnSave; };
      languages = mkAttrsOption { default = languages; };
      lsp = mkAttrsOption { default = lsp; };

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
          inherit (config.icedos) applications desktop;
          inherit (applications) zed;
          inherit (desktop) defaultEditor;

          inherit (zed)
            autosave
            extensions
            extraPackages
            fhs
            font
            formatOnSave
            theme
            languages
            lsp
            vim
            ;

          inherit (theme) dark light mode;

          inherit (lib)
            mkForce
            mkIf
            ;

          inherit (pkgs) nil nixd zed-editor-fhs;

          stylixOn = config.stylix.enable or false;

          fontNameFallback = "JetBrainsMono Nerd Font";
          fontSizeFallback = 14;
          themeDarkFallback = "One Dark Pro";
          themeLightFallback = "One Light";

          # Stylix doesn't write this key — must always emit a value. Stylix-on
          # + no override falls through to stylixVal so the key gets stylix's
          # font name/size; stylix-off + no override → fallback.
          overrideUnmanaged =
            userVal: sentinel: stylixVal: fallback:
            if stylixOn then
              if (userVal != sentinel) then mkForce userVal else stylixVal
            else if (userVal != sentinel) then
              userVal
            else
              fallback;

          # Stylix writes this key via its zed target. Skip our definition when
          # stylix is on and no override; let stylix's value win.
          overrideManaged =
            userVal: sentinel: fallback:
            if stylixOn then
              mkIf (userVal != sentinel) (mkForce userVal)
            else if (userVal != sentinel) then
              userVal
            else
              fallback;
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

                extraPackages = icedosLib.pkgs.mapper pkgs extraPackages;
                package = mkIf fhs zed-editor-fhs;

                userSettings = {
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

                  title_bar = {
                    button_layout = icedosLib.desktop.mkButtonLayoutString desktop.windows;
                    show_sign_in = false;
                  };

                  terminal = {
                    blinking = "on";
                    copy_on_select = true;
                    font_family = overrideUnmanaged font.name "" config.stylix.fonts.monospace.name fontNameFallback;
                    font_size = overrideUnmanaged font.size 0 (config.stylix.fonts.sizes.terminal or 12
                    ) fontSizeFallback;
                  };

                  vim_mode = vim;

                  buffer_font_family = overrideManaged font.name "" fontNameFallback;
                  buffer_font_size = overrideManaged font.size 0 fontSizeFallback;

                  ui_font_size =
                    if stylixOn then
                      mkIf (font.size != 0) (mkForce (font.size + 2))
                    else if (font.size != 0) then
                      font.size + 2
                    else
                      fontSizeFallback + 2;

                  theme =
                    let
                      themeAttrs = {
                        dark = if (dark != "") then dark else themeDarkFallback;
                        light = if (light != "") then light else themeLightFallback;
                        inherit mode;
                      };
                      hasUserOverride = dark != "" || light != "";
                    in
                    if stylixOn then mkIf hasUserOverride (mkForce themeAttrs) else themeAttrs;
                };
              };
            }
          ];
        }
      )
    ];

  meta.name = "zed";
}
