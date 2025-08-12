{ icedosLib, ... }:

{
  options.icedos.system.users =
    let
      inherit (icedosLib)
        mkBoolOption
        mkNumberOption
        mkStrListOption
        mkSubmoduleAttrsOption
        ;
    in
    mkSubmoduleAttrsOption { default = { }; } {
      applications.sd-inhibitor.watchers = {
        cpu = {
          enable = mkBoolOption { default = false; };
          threshold = mkNumberOption { default = 60; };
        };

        disk = {
          enable = mkBoolOption { default = false; };
          threshold = mkNumberOption { default = 10; };
        };

        network = {
          enable = mkBoolOption { default = false; };
          threshold = mkNumberOption { default = 1000000; };
        };

        pipewire = {
          enable = mkBoolOption { default = false; };
          inputsToIgnore = mkStrListOption { default = [ ]; };
          outputsToIgnore = mkStrListOption { default = [ ]; };
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
          inherit (lib)
            attrNames
            filterAttrs
            mapAttrs
            mkIf
            optional
            readFile
            ;

          cfg = config.icedos;

          getModules =
            path:
            map (dir: ./. + ("/modules/" + dir)) (
              attrNames (filterAttrs (_: v: v == "directory") (builtins.readDir path))
            );
        in
        {
          imports = getModules ./modules;

          home-manager.users = mapAttrs (user: _: {
            systemd.user.services.sd-inhibitor =
              let
                watchers = cfg.system.users.${user}.applications.sd-inhibitor.watchers;
              in
              mkIf
                (watchers.cpu.enable || watchers.disk.enable || watchers.network.enable || watchers.pipewire.enable)
                {
                  Unit = {
                    Description = "service to inhibit idle, sleep and shutdown based on device usage limits";
                    After = "graphical-session.target";
                    PartOf = "graphical-session.target";
                  };

                  Install.WantedBy =
                    [ ]
                    ++ optional (cfg.desktop.hyprland.enable) "hyprland-session.target"
                    ++ optional (lib.hasAttr "gnome" cfg.desktop) "gnome-session.target";

                  Service = {
                    ExecStart = with pkgs; "${writeShellScript "sd-inhibitor" (readFile ./sd-inhibitor.sh)}";
                    Nice = "-20";
                    Restart = "on-failure";
                    StartLimitBurst = 60;
                  };
                };
          }) cfg.system.users;
        }
      )
    ];

  meta.name = "sd-inhibitor";
}
