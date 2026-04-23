{ icedosLib, lib, ... }:

{
  options.icedos.applications.mangohud =
    let
      inherit (icedosLib) mkNumberOption mkStrOption;

      inherit ((fromTOML (lib.readFile ./config.toml)).icedos.applications.mangohud)
        fontSize
        fpsLimit
        position
        ;
    in
    {
      fontSize = mkNumberOption { default = fontSize; };
      fpsLimit = mkStrOption { default = fpsLimit; };
      position = mkStrOption { default = position; };
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
          inherit (lib) mapAttrs;
          cfg = config.icedos;
        in
        {
          home-manager.users = mapAttrs (
            user: _:
            let
              steamdeck = lib.hasAttr "steamdeck" cfg.hardware.devices;
            in
            {
              programs.mangohud = {
                enable = true;

                settings =
                  let
                    hasBattery = cfg.hardware.devices.laptop || steamdeck;
                    mangohud = cfg.applications.mangohud;
                    normalColor = "F9F9F9";
                    loadColors = "${normalColor},D09965,DC6A73";
                    reversedLoadColors = "DC6A73,D09965,${normalColor}";
                    loadValues = "70,90";
                  in
                  lib.mkMerge [
                    {
                      battery = hasBattery;
                      battery_icon = hasBattery;
                      battery_time = hasBattery;
                      cpu_load_change = true;
                      cpu_load_value = loadValues;
                      cpu_power = true;
                      cpu_temp = true;
                      engine_short_names = true;
                      fps_color_change = true;
                      fps_limit = mangohud.fpsLimit;
                      fps_value = "20,30";
                      frame_timing = false;
                      gl_vsync = 0;
                      gpu_load_change = true;
                      gpu_load_value = loadValues;
                      gpu_power = true;
                      gpu_temp = true;
                      horizontal = true;
                      hud_compact = true;
                      hud_no_margin = true;
                      offset_x = 5;
                      offset_y = 5;
                      position = mangohud.position;
                      text_outline = false;
                      vsync = 1;
                    }

                    (lib.mkIf (!(config.stylix.enable or false)) {
                      background_alpha = 0;
                      cpu_color = normalColor;
                      cpu_load_color = loadColors;
                      engine_color = normalColor;
                      font_size = mangohud.fontSize;
                      fps_color = reversedLoadColors;
                      gpu_color = normalColor;
                      gpu_load_color = loadColors;
                      text_color = normalColor;
                      vram_color = normalColor;
                    })
                  ];
              };
            }
          ) cfg.users;
        }
      )
    ];

  meta.name = "mangohud";
}
