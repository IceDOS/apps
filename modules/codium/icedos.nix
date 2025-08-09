{
  icedosLib,
  lib,
  ...
}:

{
  options.icedos =
    let
      inherit (icedosLib)
        mkBoolOption
        mkNumberOption
        mkStrOption
        mkSubmoduleAttrsOption
        ;

      applications = fromTOML (lib.fileContents ./config.toml).icedos.applications;
    in
    {
      applications.defaultEditor = mkStrOption { default = applications.defaultEditor; };

      system.users = mkSubmoduleAttrsOption { default = { }; } {
        applications.codium = {
          autoSave = mkStrOption { };
          formatOnPaste = mkBoolOption { };
          formatOnSave = mkBoolOption { };
          zoomLevel = mkNumberOption { };
        };
      };
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
          inherit (lib) mapAttrs mkIf;

          cfg = config.icedos;
          users = cfg.system.users;
        in
        {
          environment.variables.EDITOR = mkIf (
            cfg.applications.defaultEditor == "codium.desktop"
          ) "codium -n -w";

          home-manager.users = mapAttrs (
            user: _:
            let
              cfg = config.icedos;
              codium = cfg.system.users.${user}.applications.codium;
            in
            {
              programs.vscode = {
                enable = true;
                profiles.default.enableExtensionUpdateCheck = true;
                profiles.default.enableUpdateCheck = false;
                package = pkgs.vscodium;

                profiles.default.extensions = with pkgs; [
                  vscode-extensions.codezombiech.gitignore
                  vscode-extensions.dbaeumer.vscode-eslint
                  vscode-extensions.donjayamanne.githistory
                  vscode-extensions.eamodio.gitlens
                  vscode-extensions.editorconfig.editorconfig
                  vscode-extensions.esbenp.prettier-vscode
                  vscode-extensions.fabiospampinato.vscode-open-in-github
                  vscode-extensions.formulahendry.auto-close-tag
                  vscode-extensions.formulahendry.code-runner
                  vscode-extensions.gruntfuggly.todo-tree
                  vscode-extensions.jnoortheen.nix-ide
                  vscode-extensions.pkief.material-icon-theme
                  vscode-extensions.tamasfe.even-better-toml
                  vscode-extensions.timonwong.shellcheck
                  vscode-extensions.zhuangtongfa.material-theme
                ];

                profiles.default.userSettings = {
                  "[css]".editor.defaultFormatter = "esbenp.prettier-vscode";
                  "[javascript]".editor.defaultFormatter = "esbenp.prettier-vscode";
                  "[typescript]".editor.defaultFormatter = "esbenp.prettier-vscode";
                  "[typescriptreact]".editor.defaultFormatter = "esbenp.prettier-vscode";
                  diffEditor.ignoreTrimWhitespace = false;

                  editor = {
                    fontFamily = "'JetBrainsMono Nerd Font', 'Droid Sans Mono', 'monospace', monospace";
                    fontLigatures = true;
                    formatOnPaste = codium.formatOnPaste;
                    formatOnSave = codium.formatOnSave;
                    minimap.enabled = false;
                    renderWhitespace = "trailing";
                    smoothScrolling = true;
                    tabSize = 2;
                  };

                  evenBetterToml.formatter.alignComments = false;

                  files = {
                    associations."*.css" = "tailwindcss";
                    autoSave = codium.autoSave;
                    insertFinalNewline = true;
                    trimFinalNewlines = true;
                    trimTrailingWhitespace = true;
                  };

                  git = {
                    autofetch = true;
                    confirmSync = false;
                  };

                  gitlens = {
                    codeLens.enabled = false;
                    defaultDateFormat = "YYYY-MM-DD HH:mm";
                    defaultDateLocale = "system";
                    defaultDateShortFormat = "YYYY-M-D";
                    defaultTimeFormat = "HH:mm";
                    statusBar.enabled = false;

                    views.repositories = {
                      showContributors = false;
                      showStashes = true;
                      showTags = false;
                      showWorktrees = false;
                    };
                  };

                  nix.formatterPath = "nixfmt";
                  scm.showHistoryGraph = false;

                  terminal.integrated = {
                    cursorBlinking = true;
                    cursorStyle = "line";
                    smoothScrolling = true;
                  };

                  update.mode = "none";

                  window = {
                    menuBarVisibility = "toggle";
                    zoomLevel = codium.zoomLevel;
                  };

                  workbench = {
                    colorTheme = "One Dark Pro Darker";
                    iconTheme = "material-icon-theme";
                    list.smoothScrolling = true;
                    startupEditor = "none";
                    tips.enabled = false;
                  };
                };
              };
            }
          ) users;
        }
      )
    ];

  meta.name = "codium";
}
