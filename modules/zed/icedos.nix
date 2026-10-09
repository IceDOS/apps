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
        agentBridge
        autosave
        copySelectionLocation
        extensions
        extraPackages
        fhs
        font
        formatOnSave
        languages
        lazygit
        lsp
        theme
        terminalInitCommand
        vim
        ;
    in
    {
      agentBridge =
        let
          inherit (agentBridge)
            enable
            remoteLookup
            resolveTimeout
            sshTarget
            zedDb
            ;
        in
        {
          enable = mkBoolOption { default = enable; };
          remoteLookup = mkBoolOption { default = remoteLookup; };
          resolveTimeout = mkNumberOption { default = resolveTimeout; };
          sshTarget = mkStrOption { default = sshTarget; };
          zedDb = mkStrOption { default = zedDb; };
        };

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

      lazygit = {
        enable = mkBoolOption { default = lazygit.enable; };
        keybind = mkStrOption { default = lazygit.keybind; };
      };

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

      terminalInitCommand = mkStrOption { default = terminalInitCommand; };

      vim = mkBoolOption { default = vim; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          icedosLib,
          lib,
          pkgs,
          ...
        }:
        let
          inherit (config.icedos) applications desktop;
          inherit (applications) zed;

          inherit (zed)
            agentBridge
            autosave
            copySelectionLocation
            extensions
            extraPackages
            fhs
            font
            formatOnSave
            theme
            languages
            lazygit
            lsp
            terminalInitCommand
            vim
            ;

          inherit (theme) dark light mode;

          inherit (lib)
            mkForce
            mkIf
            ;

          inherit (pkgs) nil nixd zed-editor-fhs;

          # The bridge extends agent-launch: its picker and agent registry live there.
          hasAgentLaunch = icedosLib.hasModule {
            inherit config;
            url = "github:icedos/ai-tools";
            name = "agent-launch";
          };

          bridgeEnabled = agentBridge.enable && hasAgentLaunch;

          bridgeConfig = pkgs.writeText "zed-agent-bridge.json" (
            builtins.toJSON {
              inherit (agentBridge)
                remoteLookup
                resolveTimeout
                sshTarget
                zedDb
                ;
              agents = config.icedos.ai-tools.agent-launch.agents or { };
            }
          );

          # python3, not python3Minimal: the bridge needs the sqlite3 module.
          bridgeBin = pkgs.writeShellScriptBin "zed-agent-bridge" ''
            export PATH=${lib.makeBinPath [ pkgs.openssh ]}"''${PATH:+:$PATH}"
            exec ${pkgs.python3}/bin/python3 ${./lib/zed_agent_bridge.py} --config ${bridgeConfig} "$@"
          '';

          bridgePkgs = [
            bridgeBin
            # Zed's terminal_init_command takes a bare program name.
            (pkgs.writeShellScriptBin "zed-agent-launch" ''
              exec zed-agent-bridge launch
            '')
          ];

          fontNameFallback = "JetBrainsMono Nerd Font";
          fontSizeFallback = 14;
          themeDarkFallback = "One Dark Pro";
          themeLightFallback = "One Light";
        in
        {
          assertions = [
            {
              assertion = agentBridge.enable -> hasAgentLaunch;
              message = "icedos.applications.zed.agentBridge needs the agent-launch module from github:icedos/ai-tools.";
            }
          ];

          environment.variables.EDITOR = mkIf (
            desktop.applications.editor.name == "dev.zed.Zed.desktop"
          ) "zeditor -n -w";

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

                    agent.terminal_init_command =
                      if bridgeEnabled then "zed-agent-launch" else terminalInitCommand;
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

                  userTasks =
                    lib.optionals copySelectionLocation.enable [
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
                    ]
                    ++ lib.optionals lazygit.enable [
                      {
                        label = "lazygit";
                        command = "lazygit";
                        args = [ ];
                        use_new_terminal = true;
                        allow_concurrent_runs = false;
                        reveal = "always";
                        reveal_target = "dock";
                        hide = "never";
                      }
                    ];

                  userKeymaps =
                    lib.optionals copySelectionLocation.enable [
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
                    ]
                    ++ lib.optionals lazygit.enable [
                      {
                        # ctrl-alt-q is unbound in the Linux defaults, overrides, and vim keymap.
                        context = "Editor || Workspace";
                        bindings = {
                          ${lazygit.keybind} = [
                            "task::Spawn"
                            {
                              task_name = "lazygit";
                            }
                          ];
                        };
                      }
                    ];
                };

                home.packages =
                  # copy-location: copy selection's file path to clipboard
                  lib.optionals copySelectionLocation.enable [
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
                  ]
                  # The task runs bare `lazygit`; provide it so zed.lazygit.enable works
                  # without the core git module.
                  ++ lib.optionals lazygit.enable [ pkgs.lazygit ]
                  ++ lib.optionals bridgeEnabled bridgePkgs;

                programs.claude-code.settings.hooks.SessionStart =
                  mkIf (bridgeEnabled && (config.programs.claude-code.enable or false))
                    [
                      {
                        hooks = [
                          {
                            type = "command";
                            command = "zed-agent-bridge claude-hook";
                          }
                        ];
                      }
                    ];
              }
            )
          ];

          icedos.system.tips.list = [
            "Zed is a fast code editor; set its theme, font and format-on-save in config.toml."
          ]
          ++ lib.optionals zed.vim [
            "Vim keys are turned on in Zed."
          ]
          ++ lib.optionals zed.copySelectionLocation.enable [
            "In Zed, ${zed.copySelectionLocation.keybind} copies the file and line you selected."
          ]
          ++ lib.optionals zed.lazygit.enable [
            "In Zed, ${zed.lazygit.keybind} opens lazygit in the terminal dock."
          ]
          ++ lib.optionals bridgeEnabled [
            "Reopening a terminal thread in Zed's agent panel resumes the agent session that ran in it."
          ];
        }
      )
    ];

  meta.name = "zed";
}
