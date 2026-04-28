{ icedosLib, lib, ... }:

{
  options.icedos.applications.kitty =
    let
      inherit (icedosLib) mkBoolOption mkNumberOption;
      inherit (lib) mkOption readFile types;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.kitty)
        fontSize
        hideDecorations
        opacity
        ;
    in
    {
      fontSize = mkNumberOption { default = fontSize; };
      hideDecorations = mkBoolOption { default = hideDecorations; };
      opacity = mkOption {
        type = types.ints.between 1 100;
        default = opacity;
        description = "Kitty background opacity, 1-100 scale (forwarded as 0.01-1.00 to kitty).";
      };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          ...
        }:

        let
          cfg = config.icedos;

          inherit (lib)
            mkIf
            mkMerge
            mkForce
            hasAttr
            ;

          kitty = cfg.applications.kitty;
        in
        {
          home-manager.sharedModules = [
            {
              programs.kitty = mkMerge [
                {
                  enable = true;

                  settings = {
                    confirm_os_window_close = "0";
                    cursor_shape = "beam";
                    enable_audio_bell = "no";
                    hide_window_decorations = if (kitty.hideDecorations) then "yes" else "no";
                    update_check_interval = "0";
                    copy_on_select = "no";
                    wayland_titlebar_color = "background";
                  };
                }

                (mkIf (!(config.stylix.enable or false)) {
                  font.name = "JetBrainsMono Nerd Font";
                  font.size = kitty.fontSize;
                  themeFile = "OneDark-Pro";
                })

                {
                  settings.background_opacity = mkForce (toString (kitty.opacity / 100.0));
                }
              ];

              wayland.windowManager.hyprland.settings.bind =
                mkIf (hasAttr "desktop" cfg && hasAttr "hyprland" cfg.desktop)
                  [
                    "$mainMod, X, exec, kitty"
                  ];

              dconf.settings = mkIf (hasAttr "desktop" cfg && hasAttr "gnome" cfg.desktop) {
                "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/kitty" = {
                  binding = "<Super>x";
                  command = "kitty";
                  name = "Kitty";
                };

                "org/gnome/settings-daemon/plugins/media-keys".custom-keybindings = [
                  "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/kitty/"
                ];
              };
            }
          ];
        }
      )
    ];

  meta.name = "kitty";
}
