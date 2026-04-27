{ lib, ... }:

{
  options.icedos.applications.zsh =
    let
      inherit (lib) mkOption readFile;
      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.zsh) aliases;
    in
    {
      aliases = mkOption { default = aliases; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          pkgs,
          lib,
          ...
        }:

        let
          inherit (config.icedos) applications users;
          inherit (lib) mapAttrs readFile replaceStrings;

          stylixOn = config.stylix.enable or false;
          stylixColors = config.lib.stylix.colors or { };

          p10kColorTargets = [
            "local red='#FF5C57'"
            "local yellow='#F3F99D'"
            "local blue='#57C7FF'"
            "local magenta='#FF6AC1'"
            "local cyan='#9AEDFE'"
            "local white='#F1F1F0'"
          ];

          p10kColorReplacements =
            if stylixOn then
              [
                "local red='#${stylixColors.base08}'"
                "local yellow='#${stylixColors.base0A}'"
                "local blue='#${stylixColors.base0D}'"
                "local magenta='#${stylixColors.base0E}'"
                "local cyan='#${stylixColors.base0C}'"
                "local white='#${stylixColors.base07}'"
              ]
            else
              p10kColorTargets;

          p10kThemeText = replaceStrings p10kColorTargets p10kColorReplacements (readFile ./p10k-theme.zsh);
        in
        {
          fonts.packages = with pkgs; [ meslo-lgs-nf ];

          home-manager.users = mapAttrs (user: _: {
            programs.zsh = {
              enable = true;
              dotDir = "${config.home-manager.users.${user}.xdg.configHome}/zsh";
            };

            home.file = {
              ".config/zsh/p10k.zsh".source =
                "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme";

              ".config/zsh/p10k-theme.zsh".text = p10kThemeText;
            };
          }) users;

          programs.zsh = {
            enable = true;

            ohMyZsh = {
              enable = true;
              plugins = [
                "git"
                "npm"
                "sudo"
                "systemd"
              ];
            };

            autosuggestions.enable = true;
            syntaxHighlighting.enable = true;

            interactiveShellInit = ''
              if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
                source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
              fi

              [[ ! -f ~/.config/zsh/p10k.zsh ]] || source ~/.config/zsh/p10k.zsh
              [[ ! -f ~/.config/zsh/p10k-theme.zsh ]] || source ~/.config/zsh/p10k-theme.zsh
              unsetopt PROMPT_SP
            '';

            shellAliases = applications.zsh.aliases;
          };

          users.defaultUserShell = pkgs.zsh;
        }
      )
    ];

  meta.name = "zsh";
}
