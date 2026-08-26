{
  lib,
  icedosLib,
  ...
}:

{
  options.icedos.applications.zed =
    let
      inherit (lib) importTOML;

      inherit (icedosLib)
        mkAttrsOption
        mkBoolOption
        mkNumberOption
        mkStrListOption
        mkStrOption
        ;

      inherit ((importTOML ./config.toml).icedos.applications.zed)
        autosave
        copySelectionLocation
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

      copySelectionLocation = {
        enable = mkBoolOption { default = copySelectionLocation.enable; };
        keybind = mkStrOption { default = copySelectionLocation.keybind; };
      };

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
            copySelectionLocation
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

          fontNameFallback = "JetBrainsMono Nerd Font";
          fontSizeFallback = 14;
          themeDarkFallback = "One Dark Pro";
          themeLightFallback = "One Light";
        in
        {
          environment.variables.EDITOR = mkIf (defaultEditor == "dev.zed.Zed.desktop") "zeditor -n -w";

          environment.systemPackages = [
            nil
            nixd
          ];

          programs.nix-ld.enable = mkIf (!fhs) true;

          home-manager.sharedModules = [
            (
              { config, ... }:
              let
                # A disabled zed target (via disabledTargets) means stylix writes
                # nothing; fall through to our own font/theme defaults.
                stylixTarget = config.stylix.targets.zed.enable or false;

                # Stylix doesn't write this key — always emit a value: user
                # override, else stylix's value, else our fallback.
                overrideUnmanaged =
                  userVal: sentinel: stylixVal: fallback:
                  if stylixTarget then
                    if (userVal != sentinel) then mkForce userVal else stylixVal
                  else if (userVal != sentinel) then
                    userVal
                  else
                    fallback;

                # Stylix writes this key via its zed target; emit only a user override.
                overrideManaged =
                  userVal: sentinel: fallback:
                  if stylixTarget then
                    mkIf (userVal != sentinel) (mkForce userVal)
                  else if (userVal != sentinel) then
                    userVal
                  else
                    fallback;
              in
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
                      font_size = overrideUnmanaged font.size 0 config.stylix.fonts.sizes.terminal fontSizeFallback;
                    };

                    vim_mode = vim;

                    buffer_font_family = overrideManaged font.name "" fontNameFallback;
                    buffer_font_size = overrideManaged font.size 0 fontSizeFallback;

                    ui_font_size =
                      if stylixTarget then
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
                      if stylixTarget then mkIf hasUserOverride (mkForce themeAttrs) else themeAttrs;
                  };

                  userTasks = mkIf copySelectionLocation.enable [
                    {
                      # Selection via env, not argv: build_no_quote would dump raw code into zsh -c.
                      label = "copy-location: copy selection";
                      command = "copy-location";
                      args = [ ];
                      use_new_terminal = false;
                      allow_concurrent_runs = true;
                      reveal = "never";
                      hide = "on_success";
                    }
                  ];

                  userKeymaps = mkIf copySelectionLocation.enable [
                    {
                      # Free in Zed's Linux default editor keymap (collides only in panel contexts).
                      context = "Editor";
                      bindings = {
                        ${copySelectionLocation.keybind} = [
                          "task::Spawn"
                          {
                            task_name = "copy-location: copy selection";
                          }
                        ];
                      };
                    }
                  ];
                };

                # copy-location: copy selection's file path to clipboard
                home.packages = mkIf copySelectionLocation.enable [
                  (pkgs.writeShellScriptBin "copy-location" ''
                    # wl-copy execs \`cat\`, so coreutils must be on PATH for the hermetic guarantee.
                    export PATH=${
                      lib.makeBinPath [
                        pkgs.wl-clipboard
                        pkgs.xclip
                        pkgs.libnotify
                        pkgs.coreutils
                      ]
                    }"''${PATH:+:$PATH}"
                    exec ${pkgs.python3Minimal}/bin/python3 ${./lib/copy-location.py} "$@"
                  '')
                ];
              }
            )
          ];
        }
      )
    ];

  meta.name = "zed";
}
