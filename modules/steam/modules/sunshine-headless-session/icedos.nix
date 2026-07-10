{ icedosLib, lib, ... }:

{
  options.icedos.applications.steam.headlessSession = import ./options.nix { inherit icedosLib lib; };

  outputs.nixosModules =
    { inputs, ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:

        let
          cfg = config.icedos.applications.steam.headlessSession;

          inherit (lib) getExe mkDefault mkIf;
          inherit (cfg)
            excludeHostControllers
            isolateVirtualControllers
            secondarySteamSession
            secondarySteamSessionPath
            ;

          packages = import ./packages.nix { inherit pkgs inputs cfg; };
          inherit (packages)
            xdg-desktop-portal-gamescope
            sunshinePortalConfig
            gidExec
            ;

          inherit
            (import ./scripts.nix {
              inherit pkgs lib cfg;
              inherit (packages) gamescopePkg;
            })
            idleApp
            sessionApp
            ;

          steamApps = import ./apps.nix {
            inherit
              pkgs
              lib
              cfg
              sessionApp
              ;
          };
        in
        {
          # Strip the seat0 uaccess ACL from the Sunshine virtual pad so the host
          # desktop (user not in `input`) can't open it, while the injected Steam still
          # can via the setgid-`input` wrapper. Must be priority 72 (between 71-seat and
          # 73-seat-late); also force MODE 0660 + clear ACL for the racy js* node.
          services.udev.packages = mkIf isolateVirtualControllers [
            (pkgs.writeTextDir "etc/udev/rules.d/72-sunshine-headless-no-uaccess.rules" ''
              SUBSYSTEM=="input", ATTRS{name}=="Sunshine*", TAG-="uaccess", MODE="0660", RUN+="${pkgs.acl}/bin/setfacl -b $env{DEVNAME}"
            '')
          ];

          # setgid-`input` shim: only the injected Steam (which execs through it) gets
          # the `input` group and can open the uaccess-stripped pad.
          security.wrappers = mkIf isolateVirtualControllers {
            sunshine-headless-gid = {
              setgid = true;
              owner = "root";
              group = "input";
              source = "${gidExec}";
            };
          };

          # Let a local active session create + tune ONLY the sunshine-headless-steam
          # scope (the cgroup device policy for the injected Steam), without sudo.
          security.polkit.extraConfig = mkIf excludeHostControllers ''
            polkit.addRule(function(action, subject) {
              if (action.id == "org.freedesktop.systemd1.manage-units" &&
                  action.lookup("unit") == "sunshine-headless-steam.scope" &&
                  subject.local && subject.active) {
                return polkit.Result.YES;
              }
            });
          '';

          # Persistent idle gamescope so the injection target is always present.
          systemd.user.services.sunshine-headless-idle = {
            description = "Persistent idle gamescope for Sunshine headless";
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            after = [ "graphical-session.target" ];

            serviceConfig = {
              ExecStart = getExe idleApp;
              Restart = "always";
              RestartSec = "5s";
              KillSignal = "SIGKILL";
              TimeoutStopSec = "10s";
            };
          };

          environment.systemPackages = [
            idleApp
            sessionApp
          ];

          # Merge into the user's apps.json (sunshine's default is {} so lists concat).
          services.sunshine.applications.apps = steamApps;

          assertions = [
            {
              assertion = !secondarySteamSession || secondarySteamSessionPath != "";
              message = "icedos.applications.steam.headlessSession.secondarySteamSessionPath must be set (non-empty) when secondarySteamSession is enabled.";
            }
          ];

          services.sunshine.settings.audio_sink = mkDefault "steam-sunshine-headless-sink";
          services.sunshine.settings.capture = mkDefault "portal";

          # Tray libnotify calls org.freedesktop.Notifications, which isn't on the
          # private portal bus → SIGTRAP → Sunshine core-dumps mid-stream. Disable it.
          services.sunshine.settings.system_tray = mkDefault false;

          # Private D-Bus + portal frontend scoped to Sunshine, so gamescope's ScreenCast
          # never touches the host desktop portal and only Sunshine consumes its single
          # pipewire node (two consumers → "out of buffers" → Moonlight crash).
          systemd.user.services.sunshine-portal-bus = {
            description = "Private D-Bus for the Sunshine headless portal";
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            after = [ "graphical-session.target" ];
            environment.XDG_DATA_DIRS = "${xdg-desktop-portal-gamescope}/share";
            serviceConfig = {
              ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %t/sunshine-portal";
              ExecStart = "${pkgs.dbus}/bin/dbus-daemon --session --nofork --nopidfile --address=unix:path=%t/sunshine-portal/bus";
              Restart = "always";
              RestartSec = "2s";
            };
          };

          systemd.user.services.sunshine-portal = {
            description = "Private xdg-desktop-portal (gamescope) for Sunshine headless";
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            requires = [ "sunshine-portal-bus.service" ];

            # after bus ONLY — ordering after the idle service + target membership makes
            # systemd drop this start job (cycle). Backend is D-Bus-activated lazily.
            after = [ "sunshine-portal-bus.service" ];

            environment = {
              DBUS_SESSION_BUS_ADDRESS = "unix:path=%t/sunshine-portal/bus";
              XDG_DATA_DIRS = "${pkgs.xdg-desktop-portal}/share:${xdg-desktop-portal-gamescope}/share";

              # nixpkgs xdg-desktop-portal loads .portal definitions from these vars, NOT
              # XDG_DATA_DIRS — without them the gamescope backend is never found.
              NIX_XDG_DESKTOP_PORTAL_DIR = "${xdg-desktop-portal-gamescope}/share/xdg-desktop-portal/portals";
              XDG_DESKTOP_PORTAL_DIR = "${xdg-desktop-portal-gamescope}/share/xdg-desktop-portal/portals";
              XDG_CONFIG_HOME = "${sunshinePortalConfig}";
              XDG_CURRENT_DESKTOP = "gamescope";
              WAYLAND_DISPLAY = "gamescope-0";
              G_MESSAGES_DEBUG = "all"; # verbose: log exactly which backend serves ScreenCast
            };
            serviceConfig = {
              ExecStart = "${pkgs.xdg-desktop-portal}/libexec/xdg-desktop-portal --verbose";
              Restart = "always";
              RestartSec = "2s";
            };
          };

          # Sunshine's portal client uses the private bus (→ gamescope-0); the injected
          # Steam must NOT inherit it (it resets to the real session bus in scripts.nix).
          systemd.user.services.sunshine = {
            after = [ "sunshine-portal.service" ];
            environment = {
              WAYLAND_DISPLAY = "gamescope-0";
              DBUS_SESSION_BUS_ADDRESS = "unix:path=%t/sunshine-portal/bus";
            };
          };
        }
      )
    ];

  meta = {
    name = "steam-sunshine-headless-session";

    dependencies = [
      {
        modules = [
          "steam"
          "sunshine"
        ];
      }
      {
        url = "github:icedos/providers";
        modules = [
          "jovian"
        ];
      }
    ];
  };
}
