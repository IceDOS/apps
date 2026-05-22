{ icedosLib, lib, ... }:

{
  options.icedos.applications.polaris =
    let
      inherit (icedosLib) mkAttrsOption mkBoolOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.polaris)
        applications
        autoStart
        capSysAdmin
        cudaSupport
        enableBrowserStream
        openFirewall
        settings
        ;
    in
    {
      # Freeform apps.json ({ env = {}; apps = []; }). Empty -> web console keeps control.
      applications = mkAttrsOption { default = applications; };

      autoStart = mkBoolOption { default = autoStart; };
      capSysAdmin = mkBoolOption { default = capSysAdmin; };
      cudaSupport = mkBoolOption { default = cudaSupport; };
      enableBrowserStream = mkBoolOption { default = enableBrowserStream; };
      openFirewall = mkBoolOption { default = openFirewall; };

      # Freeform polaris.conf. Empty -> web console keeps control.
      settings = mkAttrsOption { default = settings; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          utils,
          ...
        }:

        let
          inherit (config.icedos) users;
          inherit (config.icedos.applications) polaris;
          inherit (icedosLib.users) mkGroupInjector;

          inherit (lib)
            getExe
            getExe'
            mkDefault
            mkIf
            optionalAttrs
            optionals
            ;

          inherit (polaris)
            applications
            autoStart
            capSysAdmin
            openFirewall
            settings
            ;

          # Ports are offset from a single base port (Sunshine-compatible layout).
          defaultPort = 47989;
          generatePorts = offsets: map (offset: (settings.port or defaultPort) + offset) offsets;

          appsFormat = pkgs.formats.json { };
          settingsFormat = pkgs.formats.keyValue { };

          appsFile = appsFormat.generate "apps.json" applications;

          # Point polaris.conf at the rendered apps.json when apps are declared.
          effectiveSettings = settings // optionalAttrs (applications != { }) { file_apps = "${appsFile}"; };

          configFile = settingsFormat.generate "polaris.conf" effectiveSettings;

          # When nothing is declared, leave ~/.config/polaris/ writable so the
          # web console stays fully editable; otherwise pass the rendered config.
          customised = settings != { } || applications != { };

          # Upstream src_assets/linux/misc/60-polaris.rules.
          udevRules = ''
            # Allows Polaris to access /dev/uinput
            KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", GROUP="input", MODE="0660", TAG+="uaccess"

            # Allows Polaris to access /dev/uhid
            KERNEL=="uhid", GROUP="input", MODE="0660", TAG+="uaccess"

            # Joypads
            KERNEL=="hidraw*", ATTRS{name}=="Polaris PS5 (virtual) pad", GROUP="input", MODE="0660", TAG+="uaccess"
            SUBSYSTEMS=="input", ATTRS{name}=="Polaris X-Box One (virtual) pad", GROUP="input", MODE="0660", TAG+="uaccess"
            SUBSYSTEMS=="input", ATTRS{name}=="Polaris gamepad (virtual) motion sensors", GROUP="input", MODE="0660", TAG+="uaccess"
            SUBSYSTEMS=="input", ATTRS{name}=="Polaris Nintendo (virtual) pad", GROUP="input", MODE="0660", TAG+="uaccess"
          '';
        in
        {
          nixpkgs.overlays = [
            (final: _super: {
              polaris = final.callPackage ./package.nix {
                inherit (polaris) cudaSupport enableBrowserStream;
              };
            })
          ];

          environment.systemPackages = [
            pkgs.polaris
            pkgs.grim
            pkgs.labwc
            pkgs.which
            pkgs.wlr-randr
            pkgs.xwayland
            pkgs.xdpyinfo
          ];

          # Virtual input devices for the streamed session.
          hardware.uinput.enable = true;

          boot.kernelModules = [
            "uhid"
            "uinput"
          ];

          services.udev.extraRules = udevRules;
          users.users = mkGroupInjector "input" users;

          # mDNS so Moonlight clients can discover the host.
          services.avahi = {
            enable = mkDefault true;

            publish = {
              enable = mkDefault true;
              userServices = mkDefault true;
            };
          };

          networking.firewall = mkIf openFirewall {
            allowedTCPPorts = generatePorts [
              (-5)
              0
              1
              21
            ];

            allowedUDPPorts = generatePorts [
              9
              10
              11
              13
              21
            ];
          };

          # CAP_SYS_ADMIN is required for DRM/KMS screen capture.
          security.wrappers.polaris = mkIf capSysAdmin {
            owner = "root";
            group = "root";
            capabilities = "cap_sys_admin+p";
            source = getExe pkgs.polaris;
          };

          # User service: mirrors packaging/linux/polaris.service.in.
          systemd.user.services.polaris = {
            description = "Polaris - self-hosted game stream host for Moonlight";

            # Inherit the full systemd user-manager PATH instead of the minimal
            # NixOS service PATH. Polaris launches user-profile apps (Steam,
            # Lutris, games) and execs labwc/setsid/display tools - none on the
            # default service PATH. labwc and the display tools are provided via
            # environment.systemPackages. Mirrors nixpkgs services.sunshine.
            environment.PATH = lib.mkForce null;

            wantedBy = mkIf autoStart [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            wants = [ "graphical-session.target" ];
            after = [ "graphical-session.target" ];

            startLimitIntervalSec = 500;
            startLimitBurst = 5;

            serviceConfig = {
              # Avoid starting before the desktop is fully initialized.
              ExecStartPre = "${getExe' pkgs.coreutils "sleep"} 5";

              ExecStart = utils.escapeSystemdExecArgs (
                [
                  (if capSysAdmin then "${config.security.wrapperDir}/polaris" else getExe pkgs.polaris)
                ]
                ++ optionals customised [ "${configFile}" ]
              );

              Restart = "on-failure";
              RestartSec = "5s";

              # Headroom for realtime capture/encode/audio workers.
              LimitRTPRIO = 95;
              LimitNICE = -10;
            };
          };
        }
      )
    ];

  meta.name = "polaris";
}
