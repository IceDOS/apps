{ icedosLib, lib, ... }:

{
  options.icedos.applications.sd-inhibitor.users =
    let
      inherit (icedosLib)
        mkBoolOption
        mkNumberOption
        mkNumberListOption
        mkStrListOption
        mkSubmoduleAttrsOption
        ;

      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.users.username.applications.sd-inhibitor)
        watchers
        ;
    in
    mkSubmoduleAttrsOption { default = { }; } {
      watchers = {
        cpu =
          let
            inherit (watchers.cpu) enable threshold;
          in
          {
            enable = mkBoolOption { default = enable; };
            threshold = mkNumberOption { default = threshold; };
          };

        disk =
          let
            inherit (watchers.disk) enable threshold;
          in
          {
            enable = mkBoolOption { default = enable; };
            threshold = mkNumberOption { default = threshold; };
          };

        network =
          let
            inherit (watchers.network) enable threshold;
          in
          {
            enable = mkBoolOption { default = enable; };
            threshold = mkNumberOption { default = threshold; };
          };

        pipewire =
          let
            inherit (watchers.pipewire) enable inputsToIgnore outputsToIgnore;
          in
          {
            enable = mkBoolOption { default = enable; };
            inputsToIgnore = mkStrListOption { default = inputsToIgnore; };
            outputsToIgnore = mkStrListOption { default = outputsToIgnore; };
          };

        ports =
          let
            inherit (watchers.ports) enable inboundPorts outboundPorts;
          in
          {
            enable = mkBoolOption { default = enable; };
            inboundPorts = mkNumberListOption { default = inboundPorts; };
            outboundPorts = mkNumberListOption { default = outboundPorts; };
          };

        gpu =
          let
            inherit (watchers.gpu) enable threshold;
          in
          {
            enable = mkBoolOption { default = enable; };
            threshold = mkNumberOption { default = threshold; };
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
            mkIf
            readFile
            ;

          cfg = config.icedos;

          sessionTargets = icedosLib.systemd.desktopSessionTargets cfg;

          getModules =
            path:
            map (dir: ./. + ("/modules/" + dir)) (
              attrNames (filterAttrs (_: v: v == "directory") (builtins.readDir path))
            );
        in
        {
          imports = getModules ./modules;

          home-manager.sharedModules = [
            (
              { config, ... }:
              {
                systemd.user.services.sd-inhibitor =
                  let
                    watchers = cfg.applications.sd-inhibitor.users.${config.home.username}.watchers;
                  in
                  mkIf
                    (
                      watchers.cpu.enable
                      || watchers.disk.enable
                      || watchers.network.enable
                      || watchers.pipewire.enable
                      || watchers.ports.enable
                      || watchers.gpu.enable
                    )
                    {
                      Unit = {
                        Description = "service to inhibit idle, sleep and shutdown based on device usage limits";
                        After = [ "graphical-session.target" ] ++ sessionTargets;
                        StartLimitIntervalSec = 60;
                        StartLimitBurst = 60;
                      };

                      Install.WantedBy = sessionTargets;

                      Service = {
                        ExecStart =
                          with pkgs;
                          "${writeShellScript "sd-inhibitor" ''
                            ${icedosLib.bash.exportSystemPath}

                            ${readFile ./sd-inhibitor.sh}
                          ''}";
                        Nice = "-20";
                        Restart = "on-failure";
                      };
                    };
              }
            )
          ];
        }
      )
    ];

  meta.name = "sd-inhibitor";
}
