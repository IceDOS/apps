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

      inherit
        ((fromTOML (lib.fileContents ./config.toml)).icedos.users.username.applications.sd-inhibitor)
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
                inherit (lib) hasAttr;
                watchers = cfg.applications.sd-inhibitor.users.${user}.watchers;
              in
              mkIf
                (
                  watchers.cpu.enable
                  || watchers.disk.enable
                  || watchers.network.enable
                  || watchers.pipewire.enable
                  || watchers.ports.enable
                )
                {
                  Unit = {
                    Description = "service to inhibit idle, sleep and shutdown based on device usage limits";
                    After = "graphical-session.target";
                    PartOf = "graphical-session.target";
                    StartLimitIntervalSec = 60;
                    StartLimitBurst = 60;
                  };

                  Install.WantedBy =
                    [ ]
                    ++ optional (hasAttr "desktop" cfg && hasAttr "cosmic" cfg.desktop) "cosmic-session.target"
                    ++ optional (hasAttr "desktop" cfg && hasAttr "gnome" cfg.desktop) "gnome-session.target"
                    ++ optional (hasAttr "desktop" cfg && hasAttr "hyprland" cfg.desktop) "hyprland-session.target";

                  Service = {
                    ExecStart =
                      with pkgs;
                      "${writeShellScript "sd-inhibitor" ''
                        base_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                        nix_system_path="/run/current-system/sw/bin"
                        nix_user_path="''${HOME}/.nix-profile/bin"
                        export PATH="''${base_path}:''${nix_system_path}:''${nix_user_path}:$PATH"

                        ${readFile ./sd-inhibitor.sh}
                      ''}";
                    Nice = "-20";
                    Restart = "on-failure";
                  };
                };
          }) cfg.users;
        }
      )
    ];

  meta.name = "sd-inhibitor";
}
