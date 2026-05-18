{ icedosLib, lib, ... }:

{
  options.icedos.applications.kitty =
    let
      inherit (icedosLib)
        mkBoolOption
        mkIntBetweenOption
        mkNumberOption
        mkStrOption
        ;

      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.kitty)
        font
        hideDecorations
        opacity
        themeFile
        ;
    in
    {
      font =
        let
          inherit (font) name size;
        in
        {
          name = mkStrOption { default = name; };
          size = mkNumberOption { default = size; };
        };

      hideDecorations = mkBoolOption { default = hideDecorations; };

      opacity = mkIntBetweenOption {
        path = "icedos.applications.kitty.opacity";
        source = ./config.toml;
        default = opacity;
        description = "Kitty background opacity, 1-100 scale (forwarded as 0.01-1.00 to kitty).";
      } 1 100;

      themeFile = mkStrOption { default = themeFile; };
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
          inherit (lib)
            hasAttr
            mkForce
            mkIf
            mkMerge
            ;

          inherit (config) icedos;
          inherit (icedos) applications desktop;
          inherit (applications) kitty;
        in
        {
          home-manager.sharedModules = [
            (
              { config, ... }:
              let
                # Stylix's kitty target is a home-manager target;
                # `disabledTargets` routes to `stylix.targets.kitty.enable =
                # false` on the HM plane. Gate on the per-target state too,
                # not just global `stylix.enable`, so a disabled kitty target
                # falls through to our own font/theme defaults instead of
                # leaving `programs.kitty.font.name` undefined.
                stylixEnabled = (config.stylix.enable or false) && (config.stylix.targets.kitty.enable or false);
              in
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

                    font.name =
                      if stylixEnabled then
                        mkIf (kitty.font.name != "") (mkForce kitty.font.name)
                      else if (kitty.font.name != "") then
                        kitty.font.name
                      else
                        "JetBrainsMono Nerd Font";

                    font.size =
                      if stylixEnabled then
                        mkIf (kitty.font.size != 0) (mkForce kitty.font.size)
                      else if (kitty.font.size != 0) then
                        kitty.font.size
                      else
                        12;

                    themeFile =
                      if stylixEnabled then
                        mkIf (kitty.themeFile != "") (mkForce kitty.themeFile)
                      else if (kitty.themeFile != "") then
                        kitty.themeFile
                      else
                        "OneDark-Pro";

                    settings.background_opacity = mkForce (toString (kitty.opacity / 100.0));
                  }
                ];

                wayland.windowManager.hyprland.settings.bind =
                  mkIf (hasAttr "desktop" icedos && hasAttr "hyprland" desktop)
                    [
                      "$mainMod, X, exec, kitty"
                    ];

                dconf.settings = mkIf (hasAttr "desktop" icedos && hasAttr "gnome" desktop) {
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
            )
          ];
        }
      )
    ];

  meta.name = "kitty";
}
