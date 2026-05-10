{ icedosLib, lib, ... }:

{
  options.icedos.applications.mangohud =
    let
      inherit (icedosLib) mkNumberOption mkStrOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.mangohud)
        cpuColor
        cpuLoadColor
        engineColor
        fontSize
        fpsColor
        fpsLimit
        gpuColor
        gpuLoadColor
        position
        textColor
        vramColor
        ;
    in
    {
      cpuColor = mkStrOption { default = cpuColor; };
      cpuLoadColor = mkStrOption { default = cpuLoadColor; };
      engineColor = mkStrOption { default = engineColor; };
      fontSize = mkNumberOption { default = fontSize; };
      fpsColor = mkStrOption { default = fpsColor; };
      fpsLimit = mkStrOption { default = fpsLimit; };
      gpuColor = mkStrOption { default = gpuColor; };
      gpuLoadColor = mkStrOption { default = gpuLoadColor; };
      position = mkStrOption { default = position; };
      textColor = mkStrOption { default = textColor; };
      vramColor = mkStrOption { default = vramColor; };
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
          inherit (lib) hasAttr;
          inherit (config.icedos) applications hardware;
          inherit (applications) mangohud;
          inherit (hardware) devices;
        in
        {
          home-manager.sharedModules = [
            (
              let
                steamdeck = hasAttr "steamdeck" devices;
              in
              {
                programs.mangohud = {
                  enable = true;

                  settings =
                    let
                      inherit (lib) mkForce mkIf;
                      hasBattery = devices.laptop || steamdeck;
                      normalColor = "F9F9F9";
                      loadColors = "${normalColor},D09965,DC6A73";
                      reversedLoadColors = "DC6A73,D09965,${normalColor}";
                      loadValues = "70,90";
                      stylixEnabled = config.stylix.enable or false;

                      override =
                        userVal: sentinel: fallback:
                        if stylixEnabled then
                          mkIf (userVal != sentinel) (mkForce userVal)
                        else if (userVal != sentinel) then
                          userVal
                        else
                          fallback;
                    in
                    {
                      background_alpha = mkForce 0;
                      battery = hasBattery;
                      battery_icon = hasBattery;
                      battery_time = hasBattery;
                      cpu_color = override mangohud.cpuColor "" normalColor;
                      cpu_load_change = true;
                      cpu_load_color = override mangohud.cpuLoadColor "" loadColors;
                      cpu_load_value = loadValues;
                      cpu_power = true;
                      cpu_temp = true;
                      engine_color = override mangohud.engineColor "" normalColor;
                      engine_short_names = true;
                      font_size = override mangohud.fontSize 0 18;
                      fps_color = override mangohud.fpsColor "" reversedLoadColors;
                      fps_color_change = true;
                      fps_limit = mangohud.fpsLimit;
                      fps_value = "20,30";
                      frame_timing = false;
                      gl_vsync = 0;
                      gpu_color = override mangohud.gpuColor "" normalColor;
                      gpu_load_change = true;
                      gpu_load_color = override mangohud.gpuLoadColor "" loadColors;
                      gpu_load_value = loadValues;
                      gpu_power = true;
                      gpu_temp = true;
                      horizontal = true;
                      hud_compact = true;
                      hud_no_margin = true;
                      offset_x = 5;
                      offset_y = 5;
                      position = mangohud.position;
                      text_color = override mangohud.textColor "" normalColor;
                      text_outline = false;
                      vram_color = override mangohud.vramColor "" normalColor;
                      vsync = 1;
                    };
                };
              }
            )
          ];
        }
      )
    ];

  meta.name = "mangohud";
}
