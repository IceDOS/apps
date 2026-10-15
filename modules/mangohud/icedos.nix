{ icedosLib, lib, ... }:

{
  options.icedos.applications.mangohud =
    let
      inherit (icedosLib) mkIntBetweenOption mkNumberOption mkStrOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.applications.mangohud)
        cpuColor
        cpuLoadColor
        engineColor
        fontSize
        fpsColor
        fpsLimit
        glVsync
        gpuColor
        gpuLoadColor
        position
        textColor
        vramColor
        vsync
        ;
    in
    {
      cpuColor = mkStrOption { default = cpuColor; };
      cpuLoadColor = mkStrOption { default = cpuLoadColor; };
      engineColor = mkStrOption { default = engineColor; };
      fontSize = mkNumberOption { default = fontSize; };
      fpsColor = mkStrOption { default = fpsColor; };
      fpsLimit = mkStrOption { default = fpsLimit; };
      glVsync = mkIntBetweenOption {
        path = "icedos.applications.mangohud.glVsync";
        source = ./config.toml;
        default = glVsync;
        description = "OpenGL swap interval. -1 lets the game decide.";
      } (-1) 4;

      gpuColor = mkStrOption { default = gpuColor; };
      gpuLoadColor = mkStrOption { default = gpuLoadColor; };
      position = mkStrOption { default = position; };
      textColor = mkStrOption { default = textColor; };
      vramColor = mkStrOption { default = vramColor; };

      vsync = mkIntBetweenOption {
        path = "icedos.applications.mangohud.vsync";
        source = ./config.toml;
        default = vsync;
        description = "Vulkan present mode index. -1 lets the game decide.";
      } (-1) 3;
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
          inherit (config.icedos) applications hardware;
          inherit (applications) mangohud;
          inherit (hardware) devices;
        in
        {
          home-manager.sharedModules = [
            (
              let
                steamdeck = icedosLib.hasModule {
                  inherit config;
                  url = "github:icedos/hardware";
                  name = "steamdeck";
                };
              in
              {
                programs.mangohud = {
                  enable = true;

                  settings =
                    let
                      inherit (lib) mkForce mkIf;
                      hasBattery = devices.laptop || steamdeck;
                      loadValues = "70,90";
                      override = userVal: sentinel: mkIf (userVal != sentinel) (mkForce userVal);
                    in
                    {
                      background_alpha = mkForce 0;
                      battery = hasBattery;
                      battery_icon = hasBattery;
                      battery_time = hasBattery;
                      cpu_color = override mangohud.cpuColor "";
                      cpu_load_change = true;
                      cpu_load_color = override mangohud.cpuLoadColor "";
                      cpu_load_value = loadValues;
                      cpu_power = true;
                      cpu_temp = true;
                      engine_color = override mangohud.engineColor "";
                      engine_short_names = true;
                      font_size = override mangohud.fontSize 0;
                      fps_color = override mangohud.fpsColor "";
                      fps_color_change = true;
                      fps_limit = mangohud.fpsLimit;
                      fps_value = "20,30";
                      frame_timing = false;
                      gl_vsync = mkIf (mangohud.glVsync != -1) mangohud.glVsync;
                      gpu_color = override mangohud.gpuColor "";
                      gpu_load_change = true;
                      gpu_load_color = override mangohud.gpuLoadColor "";
                      gpu_load_value = loadValues;
                      gpu_power = true;
                      gpu_temp = true;
                      horizontal = true;
                      hud_compact = true;
                      hud_no_margin = true;
                      offset_x = 5;
                      offset_y = 5;
                      position = mangohud.position;
                      text_color = override mangohud.textColor "";
                      text_outline = false;
                      vram_color = override mangohud.vramColor "";
                      vsync = mkIf (mangohud.vsync != -1) mangohud.vsync;
                    };
                };
              }
            )
          ];

          icedos.system.tips.list = [
            "MangoHud shows framerate, temperatures and usage on top of your games."
            "Move the MangoHud overlay with position under [icedos.applications.mangohud]."
          ];
        }
      )
    ];

  meta.name = "mangohud";
}
