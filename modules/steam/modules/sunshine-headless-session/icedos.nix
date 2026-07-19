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

          inherit (lib) mkDefault mkIf;

          inherit (cfg)
            excludeHostControllers
            isolateVirtualControllers
            secondarySteamSession
            secondarySteamSessionPath
            steamOS
            ;

          packages = import ./packages.nix {
            inherit
              pkgs
              lib
              inputs
              cfg
              ;

          };
          inherit (packages)
            xdg-desktop-portal-gamescope
            sunshinePortalConfig
            gidExec
            ;

          inherit
            (import ./scripts.nix {
              inherit pkgs lib cfg;
              inherit (packages) gamescopePkg steamosSessionSelect;
            })
            sessionApp
            ;

          steamApps = import ./apps.nix {
            inherit
              pkgs
              lib
              cfg
              config
              sessionApp
              ;
          };

          # Second, independent Sunshine instance for the REAL physical desktop (opt-in).
          desktopCapture = import ./desktop-capture.nix {
            inherit pkgs lib;
            cfg = cfg.desktopCapture;
          };
        in
        {
          # Strip the seat0 uaccess ACL from the Sunshine virtual pad so the host
          # desktop (user not in `input`) can't open it, while the injected Steam still
          # can via the setgid-`input` wrapper. Must be priority 72 (between 71-seat and
          # 73-seat-late); also force MODE 0660 + clear ACL for the racy js* node.
          services.udev.packages =
            lib.optional isolateVirtualControllers (
              pkgs.writeTextDir "etc/udev/rules.d/72-sunshine-headless-no-uaccess.rules" ''
                SUBSYSTEM=="input", ATTRS{name}=="Sunshine*", TAG-="uaccess", MODE="0660", RUN+="${pkgs.acl}/bin/setfacl -b $env{DEVNAME}"
              ''
            )
            # Steam's Deck UI (-steamos3) opens /dev/rfkill O_RDWR to read/monitor/control
            # the radios. Default perms are root:root 0664 → read-only for a non-active-seat
            # user; systemd's 70-uaccess.rules grants rw only to the ACTIVE seat session, so a
            # headless / boot-time -steamos3 Steam has no ACL → its O_RDWR open fails → it
            # force-disables Bluetooth and its radio UI desyncs from the system.
            # Hand rfkill to the `input` GROUP (not `users`): that group has NO human members,
            # so ONLY the injected Steam — which the setgid-`input` shim runs as real gid
            # `input` — can open the node. Under -steamos3 the launcher always routes Steam
            # through that shim (scripts.nix gid_wrap), independent of isolateVirtualControllers,
            # so radio access works whenever steamOS. NB: /dev/rfkill is one node for ALL
            # radios, so this is BT + Wi-Fi on/off, not BT-only — no per-radio node to scope
            # to. Priority 70 (must sort before 73-seat-late; extraRules→99-local is too late,
            # nixpkgs#308681) — ship as a package like the 72- rule above.
            ++ lib.optional steamOS (
              pkgs.writeTextDir "etc/udev/rules.d/70-steam-rfkill-access.rules" ''
                SUBSYSTEM=="misc", KERNEL=="rfkill", GROUP="input", MODE="0660"
              ''
            );

          # setgid-`input` shim: only the injected Steam (which execs through it) gets the
          # `input` group — needed to open the uaccess-stripped pad (isolateVirtualControllers)
          # AND the input-group /dev/rfkill node under -steamos3 (radio access). Built for either.
          security.wrappers = mkIf (isolateVirtualControllers || steamOS) {
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

          # Merge into the user's apps.json (sunshine's default is {} so lists concat).
          services.sunshine.applications.apps = steamApps;

          assertions = [
            {
              assertion = !secondarySteamSession || secondarySteamSessionPath != "";
              message = "icedos.applications.steam.headlessSession.secondarySteamSessionPath must be set (non-empty) when secondarySteamSession is enabled.";
            }
            {
              assertion =
                !(cfg.desktopCapture.enable && cfg.desktopCapture.backend == "kms")
                || config.icedos.applications.sunshine.capSysAdmin;
              message = "icedos.applications.steam.headlessSession.desktopCapture.backend = \"kms\" requires icedos.applications.sunshine.capSysAdmin = true (the setcap wrapper Sunshine needs for raw KMS/DRM capture).";
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

          # Boot-time idle gamescope: Sunshine probes the encoder/display at stream LAUNCH,
          # before it runs the app prep-cmd that would spawn gamescope — so a display must
          # already exist or the probe fails with 503. Kick the shared gamescope unit
          # (sunshine-headless-gamescope.service) at an SDR fallback res; the first client
          # `start` restarts it to the client's resolution/HDR if different.
          systemd.user.services.sunshine-headless-idle = {
            description = "Boot-time idle gamescope so Sunshine's display probe passes";
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            after = [ "graphical-session.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${lib.getExe sessionApp} idle";
            };
          };

          # Sunshine's portal client uses the private bus (→ gamescope-0); the injected
          # Steam must NOT inherit it (it resets to the real session bus in scripts.nix).
          # Gate startup on the idle gamescope + portal: Sunshine enumerates the display via
          # the portal ScreenCast at STARTUP and never recovers if it finds nothing (it stays
          # up returning 503 — the launch-time re-probe does not rescue a failed startup), so
          # it must not start before gamescope-0 / the portal are ready. The wait also gives
          # the portal time to be D-Bus-ready. Restart=always because the ~2-3s gate delay can
          # lose a transient race for port 47984 (Sunshine exits 0 on that bind failure, so
          # on-failure never retries); a retry binds once the holder releases. On a clean start
          # Sunshine stays running, so restart only fires on the failure path.
          systemd.user.services.sunshine = {
            after = [
              "sunshine-headless-idle.service"
              "sunshine-portal.service"
            ];
            wants = [ "sunshine-headless-idle.service" ];
            environment = {
              WAYLAND_DISPLAY = "gamescope-0";
              DBUS_SESSION_BUS_ADDRESS = "unix:path=%t/sunshine-portal/bus";
            };
            serviceConfig = {
              ExecStartPre = [
                # A stale portal restore token makes Sunshine's startup ScreenCast hang — it
                # waits to restore a dead session and never binds its ports. Drop it so each
                # start re-requests a fresh ScreenCast (the gamescope portal auto-grants, no
                # prompt), so a leftover token from a prior crash can't wedge startup.
                "${pkgs.coreutils}/bin/rm -f %h/.config/sunshine/portal_token %h/.config/sunshine/portal_token.bak"
                (pkgs.writeShellScript "wait-gamescope" ''
                  for _ in $(seq 1 200); do
                    [ -S "$XDG_RUNTIME_DIR/gamescope-0" ] && exit 0
                    sleep 0.05
                  done
                  echo "timeout waiting for gamescope-0" >&2
                  exit 1
                '')
              ];
              Restart = lib.mkForce "always";
              RestartSec = lib.mkForce "3s";
              # Sunshine's own shutdown watchdog hangs ~10s on SIGTERM (audio teardown), then
              # force-traps itself (coredump) and leaks its portal ScreenCast session — which
              # then hangs the NEXT start. Cap the stop so systemd SIGKILLs it quickly instead;
              # the clean D-Bus disconnect lets the gamescope portal reap the session.
              TimeoutStopSec = lib.mkForce "5s";
            };
            unitConfig.StartLimitIntervalSec = lib.mkForce 0;
          };

          # Second, independent Sunshine instance for the REAL physical desktop (see
          # desktop-capture.nix). Kept entirely separate from the gamescope-pinned primary:
          # its own ports, its own isolated state/pairing, and it inherits the real Plasma
          # Wayland session (so capture=portal → KWin ScreenCast) instead of gamescope-0.
          systemd.user.services.sunshine-desktop = mkIf cfg.desktopCapture.enable desktopCapture.service;

          networking.firewall = mkIf (
            cfg.desktopCapture.enable && cfg.desktopCapture.openFirewall
          ) desktopCapture.firewall;
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
