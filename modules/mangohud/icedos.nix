{ icedosLib, ... }:

{
  options.icedos.applications.mangohud.fpsLimit = icedosLib.mkStrOption { default = "0"; };

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
                    portable = cfg.hardware.devices.laptop && steamdeck;
                  in
                  {
                    background_alpha = 0;
                    battery = portable;
                    battery_icon = portable;
                    battery_time = portable;
                    cpu_color = "FFFFFF";
                    cpu_power = true;
                    cpu_temp = true;
                    engine_color = "FFFFFF";
                    engine_short_names = true;
                    font_size = 18;
                    fps_color = "FFFFFF";
                    fps_limit = cfg.applications.mangohud.fpsLimit;
                    frame_timing = false;
                    frametime = false;
                    gl_vsync = 0;
                    gpu_color = "FFFFFF";
                    gpu_power = true;
                    gpu_temp = true;
                    horizontal = true;
                    hud_compact = true;
                    hud_no_margin = true;
                    no_small_font = true;
                    offset_x = 5;
                    offset_y = 5;
                    text_color = "FFFFFF";
                    toggle_fps_limit = "Ctrl_L+Shift_L+F1";
                    vram_color = "FFFFFF";
                    vsync = 1;
                  };
              };
            }
          ) cfg.users;
        }
      )
    ];

  meta.name = "mangohud";
}
