{
  icedosLib,
  lib,
  ...
}:

{
  options.icedos.applications.codium =
    let
      inherit (icedosLib)
        mkBoolOption
        mkNumberOption
        mkStrOption
        mkUsersOption
        ;

      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.codium.users.username)
        autoSave
        colorTheme
        fontSize
        formatOnPaste
        formatOnSave
        zoomLevel
        ;
    in
    {
      users = mkUsersOption {
        autoSave = mkStrOption { default = autoSave; };
        colorTheme = mkStrOption { default = colorTheme; };
        fontSize = mkNumberOption { default = fontSize; };
        formatOnPaste = mkBoolOption { default = formatOnPaste; };
        formatOnSave = mkBoolOption { default = formatOnSave; };
        zoomLevel = mkNumberOption { default = zoomLevel; };
      };
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
          inherit (lib) mkForce mkIf;
          inherit (config) icedos;
          inherit (icedos) applications desktop;
          inherit (applications) codium;
          inherit (desktop) defaultEditor;

          stylixEnabled = config.stylix.enable or false;
        in
        {
          icedos.applications.codium.users = icedosLib.users.genDefaults {
            inherit (icedos) users;
          };

          environment.variables.EDITOR = mkIf (defaultEditor == "codium.desktop") "codium -n -w";

          home-manager.sharedModules = [
            (
              { config, ... }:

              let
                inherit (codium.users.${config.home.username})
                  autoSave
                  colorTheme
                  fontSize
                  formatOnPaste
                  formatOnSave
                  zoomLevel
                  ;
              in
              {
                programs.vscodium = {
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
                      inherit formatOnPaste formatOnSave;

                      fontFamily = mkIf (
                        !stylixEnabled
                      ) "'JetBrainsMono Nerd Font', 'Droid Sans Mono', 'monospace', monospace";

                      fontLigatures = true;
                      minimap.enabled = false;
                      renderWhitespace = "trailing";
                      smoothScrolling = true;
                      tabSize = 2;
                    };

                    "editor.fontSize" =
                      if stylixEnabled then
                        mkIf (fontSize != 0) (mkForce fontSize)
                      else if (fontSize != 0) then
                        fontSize
                      else
                        14;

                    evenBetterToml.formatter.alignComments = false;

                    files = {
                      inherit autoSave;

                      associations."*.css" = "tailwindcss";
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

                    "terminal.integrated.fontSize" =
                      if stylixEnabled then
                        mkIf (fontSize != 0) (mkForce fontSize)
                      else if (fontSize != 0) then
                        fontSize
                      else
                        14;

                    update.mode = "none";

                    window = {
                      inherit zoomLevel;

                      menuBarVisibility = "toggle";
                    };

                    workbench = {
                      iconTheme = "material-icon-theme";
                      list.smoothScrolling = true;
                      startupEditor = "none";
                      tips.enabled = false;
                    };

                    "workbench.colorTheme" =
                      if stylixEnabled then
                        mkIf (colorTheme != "") (mkForce colorTheme)
                      else
                        mkIf (colorTheme != "") colorTheme;
                  };
                };
              }
            )
          ];
        }
      )
    ];

  meta.name = "codium";
}
