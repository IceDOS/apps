{ icedosLib, lib, ... }:

{
  options.icedos.applications.steam.headless-session = import ./options.nix {
    inherit icedosLib lib;
  };

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
          cfg = config.icedos.applications.steam.headless-session;

          inherit (lib) mkIf mkMerge;

          inherit (cfg)
            excludeHostControllers
            inputInjection
            isolateVirtualControllers
            pauseOnDisconnect
            port
            secondarySteamSession
            secondarySteamSessionPath
            steamOS
            ;

          # Non-seat0 seat: inputtino suffixes devices with it; udev rules stay scoped here.
          headlessSeat = "seat-headless";

          # One flag gates the input bridge (wrapper, group, membership) so they can't drift.
          bridgeNeeded = isolateVirtualControllers || steamOS || inputInjection;

          packages = import ./packages.nix {
            inherit
              pkgs
              lib
              inputs
              cfg
              ;

            steamPkg = ((import ../../lib/resolved-steam.nix) { inherit config pkgs; }).resolved;
            sunshinePkg = pkgs.sunshine;
          };

          inherit (packages)
            xdg-desktop-portal-gamescope
            sunshinePortalConfig
            gidExec
            inputBridgeGroup
            gamescopePkg
            ;

          inherit
            (import ./scripts.nix {
              inherit pkgs lib cfg;
              inherit headlessSeat;
              inherit (packages) gamescopePkg steamPkg steamosSessionSelect;
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

          headlessDaemon = import ./daemon.nix {
            inherit
              pkgs
              lib
              cfg
              headlessSeat
              bridgeNeeded
              sessionApp
              steamApps
              ;
          };

          # Custom session.conf: standard servicedirs + the gamescope portal's D-Bus service dir,
          # so dbus-daemon can D-Bus-activate org.freedesktop.impl.portal.desktop.gamescope.
          sunshinePortalBusConf = pkgs.writeText "sunshine-portal-bus.conf" ''
            <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
             "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
            <busconfig>
              <type>session</type>
              <keep_umask/>
              <auth>EXTERNAL</auth>
              <!-- config-file mode makes dbus-daemon require a listen element here;
                   the unit passes address= on the command line, which overrides it. -->
              <listen>unix:tmpdir=/tmp</listen>
              <standard_session_servicedirs />
              <servicedir>${xdg-desktop-portal-gamescope}/share/dbus-1/services</servicedir>
              <policy context="default">
                <allow send_destination="*" eavesdrop="true"/>
                <allow eavesdrop="true"/>
                <allow own="*"/>
              </policy>
              <limit name="max_incoming_bytes">1000000000</limit>
              <limit name="max_incoming_unix_fds">250000000</limit>
              <limit name="max_outgoing_bytes">1000000000</limit>
              <limit name="max_outgoing_unix_fds">250000000</limit>
              <limit name="max_message_size">1000000000</limit>
              <limit name="service_start_timeout">120000</limit>
              <limit name="auth_timeout">240000</limit>
              <limit name="pending_fd_timeout">150000</limit>
              <limit name="max_completed_connections">100000</limit>
              <limit name="max_incomplete_connections">10000</limit>
              <limit name="max_connections_per_user">100000</limit>
              <limit name="max_pending_service_starts">10000</limit>
              <limit name="max_names_per_connection">50000</limit>
              <limit name="max_match_rules_per_connection">50000</limit>
              <limit name="max_replies_per_connection">50000</limit>
            </busconfig>
          '';
        in
        {
          # The whole block below is the HEADLESS session; the primary is untouched.

          # Strip uaccess from the headless pads (seat-suffixed, priority 72): only the
          # shim-promoted Steam can open them.
          services.udev.packages =
            lib.optional isolateVirtualControllers (
              pkgs.writeTextDir "etc/udev/rules.d/72-sunshine-headless-no-uaccess.rules" ''
                SUBSYSTEM=="input", ATTRS{name}=="Sunshine* (${headlessSeat})*", TAG-="uaccess", MODE="0660", RUN+="${pkgs.acl}/bin/setfacl -b $env{DEVNAME}"
              ''
            )
            # Same for inputInjection's passthrough devices (EVIOCGRAB alone leaks input).
            ++ lib.optional inputInjection (
              pkgs.writeTextDir "etc/udev/rules.d/72-sunshine-headless-input-no-uaccess.rules" ''
                SUBSYSTEM=="input", ATTRS{name}=="*passthrough (${headlessSeat})*", TAG-="uaccess", MODE="0660", RUN+="${pkgs.acl}/bin/setfacl -b $env{DEVNAME}"
              ''
            )
            # -steamos3 Steam opens /dev/rfkill O_RDWR; give it to `input` (no human members).
            ++ lib.optional steamOS (
              pkgs.writeTextDir "etc/udev/rules.d/70-steam-rfkill-access.rules" ''
                SUBSYSTEM=="misc", KERNEL=="rfkill", GROUP="input", MODE="0660"
              ''
            );

          # gamescope CAP_SYS_NICE wrapper (cap-only, setuid=false, always): lets gamescope
          # SetNice(-20) + --rt. Registered regardless of the input bridge — the gid shim's
          # setgid exec clears ambient caps, so the cap must enter via the wrapper it EXECs
          # (chain: shim -> this wrapper -> gamescope). Mirrors the kwin_wayland cap wrapper.
          security.wrappers = mkMerge [
            (mkIf bridgeNeeded {
              # Mode A (setgid `input`): Steam/gamescope. Daemon must NOT use it
              # (gid-`input` fails the portal's /proc/<pid>/root check -> 503).
              sunshine-headless-gid = {
                setgid = true;
                owner = "root";
                group = "input";
                source = "${gidExec}";
              };
              # Mode B (setuid root, daemon only): keeps caller gids, adds `input`, drops root.
              sunshine-headless-gid-root = {
                setuid = true;
                owner = "root";
                group = inputBridgeGroup;
                permissions = "u+rx,g+x";
                source = "${gidExec}";
              };
            })
            {
              sunshine-headless-gamescope = {
                owner = "root";
                group = "root";
                source = "${gamescopePkg}/bin/gamescope";
                capabilities = "cap_sys_nice+pie";
              };
            }
          ];

          # Marker group the shim's caller gate checks; the wrapper turns it into `input`.
          users.groups = mkIf bridgeNeeded {
            ${inputBridgeGroup} = { };
          };

          users.users = mkIf bridgeNeeded (
            icedosLib.users.mkGroupInjector inputBridgeGroup (config.icedos.users)
          );

          # -steamos3 Steam needs InputPlumber for controller ordering/routing.
          services.inputplumber.enable = mkIf steamOS true;

          # Let the local session manage the injected-Steam scope without sudo
          # (scope creation, DeviceAllow refresh, freeze/thaw).
          security.polkit.extraConfig = mkIf (excludeHostControllers || pauseOnDisconnect) ''
            polkit.addRule(function(action, subject) {
              if (action.id == "org.freedesktop.systemd1.manage-units" &&
                  action.lookup("unit") == "sunshine-headless-steam.scope" &&
                  subject.local && subject.active) {
                return polkit.Result.YES;
              }
            });
          '';

          assertions = [
            {
              assertion = !secondarySteamSession || secondarySteamSessionPath != "";
              message = "icedos.applications.steam.headless-session.secondarySteamSessionPath must be set (non-empty) when secondarySteamSession is enabled.";
            }
            {
              # The shim assumes `input` has no human members; any voids the caller gate.
              assertion =
                !bridgeNeeded
                || !(lib.any (
                  name:
                  let
                    u = config.users.users.${name};
                  in
                  u.isNormalUser
                  && (
                    lib.elem "input" (u.extraGroups or [ ])
                    || lib.elem name (config.users.groups.input.members or [ ])
                    || u.group == "input"
                  )
                ) (lib.attrNames config.users.users));
              message = "The setgid-`input` shim assumes the `input` group has no human members, but at least one normal (human) user is in `input` (hand-written icedos.users.<name>.extraGroups, or the input-remapper module which injects every user — remove `input-remapper` from the apps repo's `modules` list, not a user entry). Remove input-remapper, or turn off isolateVirtualControllers/steamOS/inputInjection (then the shim is not built); input membership defeats the uaccess isolation the shim backs.";
            }
            {
              # Base port must differ from the primary's (the bind loser loops in Restart=always).
              assertion = port != (config.services.sunshine.settings.port or 47989);
              message = "icedos.applications.steam.headless-session.port (${toString port}) must differ from the primary sunshine instance's port (${
                toString (config.services.sunshine.settings.port or 47989)
              }) — two Sunshine daemons cannot share a TCP/UDP base port.";
            }
            {
              # openFirewall opens port+21 (RTSP); cap so it stays in NixOS' port range.
              assertion = port + 21 <= 65535;
              message = "icedos.applications.steam.headless-session.port (${toString port}) must be <= 65514 because the openFirewall rule opens the derived port+21 (RTSP) block.";
            }
          ];

          # Rename steamwebhelper's PulseAudio app: WirePlumber's shared "Chromium" key
          # would poison desktop Chromium apps.
          services.pipewire.extraConfig.pipewire-pulse."90-steam-headless-audio-name" = {
            "pulse.rules" = [
              {
                matches = [ { "application.process.binary" = "steamwebhelper"; } ];
                actions.update-props."application.name" = "Steam";
              }
            ];
          };

          # Private D-Bus + portal so ScreenCast never touches the host portal.
          systemd.user.services.sunshine-portal-bus = {
            description = "Private D-Bus for the Sunshine headless portal";
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            serviceConfig = {
              ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %t/sunshine-portal";
              ExecStart = "${pkgs.dbus}/bin/dbus-daemon --nofork --nopidfile --address=unix:path=%t/sunshine-portal/bus --config-file=${sunshinePortalBusConf}";
              Restart = "always";
              RestartSec = "2s";

              # No namespacing/seccomp: they imply a user namespace, which breaks the portal checks.
              UMask = "0027";
            };
          };

          systemd.user.services.sunshine-portal = {
            description = "Private xdg-desktop-portal (gamescope) for Sunshine headless";
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            requires = [ "sunshine-portal-bus.service" ];

            # After bus only (idle/target ordering would cycle); backend is D-Bus-activated.
            after = [ "sunshine-portal-bus.service" ];

            environment = {
              DBUS_SESSION_BUS_ADDRESS = "unix:path=%t/sunshine-portal/bus";
              XDG_DATA_DIRS = "${pkgs.xdg-desktop-portal}/share:${xdg-desktop-portal-gamescope}/share";

              # xdg-desktop-portal reads .portal defs from these vars, not XDG_DATA_DIRS.
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

              # No namespacing/seccomp: user namespace trips is_sandboxed() -> 503.
              UMask = "0027";
            };
          };

          # Boot-time idle gamescope: Sunshine's display probe needs one before prep-cmd spawns it.
          systemd.user.services.sunshine-headless-idle = {
            description = "Boot-time idle gamescope so Sunshine's display probe passes";
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${lib.getExe sessionApp} idle";

              PrivateTmp = true;
              NoNewPrivileges = true;
              ProtectClock = true;
              ProtectKernelTunables = true;
              ProtectKernelModules = true;
              ProtectControlGroups = true;
              RestrictRealtime = true;
              RestrictSUIDSGID = true;
              UMask = "0027";
            };
          };

          # Recycler: tears the session down after sessionIdleTimeout without a stream,
          # and regrows the minimal probe gamescope after gamescopeRegrowTimeout with no
          # gamescope at all. Hardened like idle.service; it systemd-runs gamescope too.
          systemd.user.services.sunshine-headless-recycle = {
            description = "Sunshine headless session recycler (idle teardown + probe gamescope regrow)";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${lib.getExe sessionApp} recycle";
              PrivateTmp = true;
              NoNewPrivileges = true;
              ProtectClock = true;
              ProtectKernelTunables = true;
              ProtectKernelModules = true;
              ProtectControlGroups = true;
              RestrictRealtime = true;
              RestrictSUIDSGID = true;
              UMask = "0027";
            };
          };

          systemd.user.timers.sunshine-headless-recycle = {
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            timerConfig = {
              Unit = "sunshine-headless-recycle.service";
              OnBootSec = "1min";
              OnUnitActiveSec = "30s";
            };
          };

          # The headless daemon: a second, independent Sunshine pinned to the private portal.
          systemd.user.services.sunshine-headless = headlessDaemon.service;

          networking.firewall = mkIf cfg.openFirewall headlessDaemon.firewall;
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
