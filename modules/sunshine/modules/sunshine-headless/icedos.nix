{ icedosLib, lib, ... }:

{
  options.icedos.applications.sunshine-headless = import ./options.nix {
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
          cfg = config.icedos.applications.sunshine-headless;

          inherit (lib) mkIf mkMerge;

          inputInjection = cfg.gamescope.inputInjection;
          isolateVirtualControllers = cfg.session.controllers.isolateVirtual;
          port = cfg.session.sunshine.port;

          # Non-seat0 seat: inputtino suffixes devices with it; udev rules stay scoped here.
          headlessSeat = "seat-headless";

          # A per-app override uses null to mean "inherit the module-global value".
          pick = v: fallback: if v == null then fallback else v;

          # A slug keys shell function names and runtime paths, so keep it [a-z0-9_].
          mkSlug =
            name:
            let
              mapped = lib.concatMapStrings (c: if builtins.match "[a-z0-9]" c != null then c else "_") (
                lib.stringToCharacters (lib.toLower name)
              );
              # Runs of underscores would otherwise survive a single replacement pass.
              collapse =
                s:
                if builtins.match "(.*)__(.*)" s == null then
                  s
                else
                  collapse (builtins.replaceStrings [ "__" ] [ "_" ] s);
            in
            collapse mapped;

          # Apps (falling back to a name-derived slug) drive the scripts, the Sunshine app
          # list and the per-app scopes, so resolve them once here and share the result.
          apps = map (
            app:
            app
            // {
              slug = if app.slug != "" then app.slug else mkSlug app.name;
              # Null per-app overrides inherit the module-global gamescope value.
              gamescope = lib.mapAttrs (k: v: if v == null then cfg.gamescope.${k} else v) app.gamescope;
              session = {
                idleTimeout = pick app.session.idleTimeout cfg.session.idleTimeout;
                pauseOnDisconnect = pick app.session.pauseOnDisconnect cfg.session.pauseOnDisconnect;
                controllers.excludeHost = pick app.session.controllers.excludeHost cfg.session.controllers.excludeHost;
              };
            }
          ) cfg.apps;

          # One flag gates the input bridge (wrapper, group, membership) so they can't drift.
          bridgeNeeded = isolateVirtualControllers || inputInjection || lib.any (app: app.shim) apps;

          packages = import ./packages.nix {
            inherit
              pkgs
              lib
              inputs
              cfg
              apps
              ;

            sunshinePkg = pkgs.sunshine;
            # Only the shim's TEST_MAIN build assert reads this, as an example of a live
            # target name; the runtime gate is shape-based, so a lookup failure is fine.
            steamVersion = pkgs.steam.version or "0";
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
              inherit
                pkgs
                lib
                cfg
                apps
                ;
              inherit headlessSeat;

              inherit (packages)
                gamescopePkg
                xnudge
                ;
            })
            sessionApp
            ;

          sunshineApps = import ./apps.nix {
            inherit lib apps sessionApp;
          };

          headlessDaemon = import ./daemon.nix {
            inherit
              pkgs
              lib
              cfg
              headlessSeat
              bridgeNeeded
              sessionApp
              ;

            apps = sunshineApps;
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

          # Strip uaccess from the headless pads (seat-suffixed, priority 72): only a
          # shim-promoted app can open them (group `input` has no human members).
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
            # A DualSense pad comes from uhid, and /dev/uhid is root-only by default, so a
            # client that asks for one gets no pad at all (Sunshine logs `Gamepad ds5 is
            # disabled due to Permission denied`). Group `input` has no human members and the
            # shim-promoted daemon holds it, so hand that group the device.
            ++ lib.optional bridgeNeeded (
              pkgs.writeTextDir "etc/udev/rules.d/72-sunshine-headless-uhid.rules" ''
                KERNEL=="uhid", GROUP="input", MODE="0660"
              ''
            )
            # The session creates devices while an app runs: the client's pad is announced a
            # few seconds after the app started. Each app scope allows input devices per node,
            # so refresh that list inside the udev event, before libudev clients hear about the
            # device, because SDL opens a pad exactly then. Without this the scope denies that
            # first open and the app never sees a Moonlight controller.
            ++
              lib.optional
                (lib.any (app: app.session.controllers.excludeHost || app.session.pauseOnDisconnect) apps)
                (
                  pkgs.writeTextDir "etc/udev/rules.d/72-sunshine-headless-scope-refresh.rules" ''
                    SUBSYSTEM=="input", ATTRS{name}=="Sunshine* (${headlessSeat})*", RUN+="${lib.getExe sessionApp} refresh"
                    SUBSYSTEM=="input", ATTRS{name}=="*passthrough (${headlessSeat})*", RUN+="${lib.getExe sessionApp} refresh"
                    # A hidraw node has no ATTRS{name} (the HID device keeps the name in
                    # HID_NAME), so match on the subsystem and let refresh filter.
                    SUBSYSTEM=="hidraw", RUN+="${lib.getExe sessionApp} refresh"
                  ''
                );

          # The gid shim's setgid exec clears ambient caps, so CAP_SYS_NICE has to come from
          # a wrapper the shim execs. Always registered; gamescope needs it for SetNice and --rt.
          security.wrappers = mkMerge [
            (mkIf bridgeNeeded {
              # Mode A (setgid `input`) is for apps and gamescope only; the daemon running
              # as gid `input` fails the portal's /proc/<pid>/root check and gets a 503.
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

          # Let the local session manage the injected app scopes without sudo (scope creation,
          # DeviceAllow refresh, freeze/thaw), one arm per app scope, and let this module's own
          # group take the locks a session-less app needs: outside a session polkit wants auth
          # for inhibit-block-sleep (inhibit-block-idle is allow_any) and denies the
          # power-profile hold outright, so proton-launch would never exec the game.
          security.polkit.extraConfig =
            mkIf (lib.any (app: app.session.controllers.excludeHost || app.session.pauseOnDisconnect) apps)
              ''
                polkit.addRule(function(action, subject) {
                  if (action.id == "org.freedesktop.systemd1.manage-units" &&
                      (${
                        lib.concatMapStrings (app: ''
                          action.lookup("unit") == "sunshine-headless-${app.slug}.scope" ||
                        '') apps
                      } false) &&
                      subject.local && subject.active) {
                    return polkit.Result.YES;
                  }
                });
                ${lib.optionalString bridgeNeeded ''
                  polkit.addRule(function(action, subject) {
                    if ((action.id == "org.freedesktop.login1.inhibit-block-sleep" ||
                         action.id == "org.freedesktop.UPower.PowerProfiles.hold-profile") &&
                        subject.isInGroup("${inputBridgeGroup}")) {
                      return polkit.Result.YES;
                    }
                  });
                ''}
              '';

          assertions = [
            {
              # Names are the CLI key (`sunshine-headless start <name>`) and the
              # Sunshine shortcut label; duplicates would collide on the runtime paths.
              assertion = lib.all (app: app.name != "") apps;
              message = "icedos.applications.sunshine-headless.apps entries need a non-empty name.";
            }
            {
              assertion = lib.unique (map (app: app.name) apps) == map (app: app.name) apps;
              message = "icedos.applications.sunshine-headless.apps names must be unique.";
            }
            {
              assertion = lib.all (app: builtins.match "[a-zA-Z0-9_]+" app.slug != null) apps;
              message = "icedos.applications.sunshine-headless.apps slugs must match [a-zA-Z0-9_]+ (derived from the name; override with `slug`).";
            }
            {
              assertion = lib.unique (map (app: app.slug) apps) == map (app: app.slug) apps;
              message = "icedos.applications.sunshine-headless.apps slugs must be unique.";
            }
            {
              # Sunshine splits the generated app command itself and only strips double
              # quotes, so a name with one cannot be passed as a single argument.
              assertion = lib.all (app: !(lib.hasInfix "\"" app.name)) apps;
              message = "icedos.applications.sunshine-headless.apps names must not contain a double quote (Sunshine splits the generated app command itself; use `slug`-friendly punctuation instead).";
            }
            {
              # An app with neither a command nor a start hook would launch nothing.
              assertion = lib.all (app: app.command != [ ] || app.hooks.start != "") apps;
              message = "icedos.applications.sunshine-headless.apps entries need a command or a start hook.";
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
              message = "The setgid-`input` shim assumes the `input` group has no human members, but at least one normal (human) user is in `input` (hand-written icedos.users.<name>.extraGroups, or the input-remapper module which injects every user — remove `input-remapper` from the apps repo's `modules` list, not a user entry). Remove input-remapper, or turn off isolateVirtual/inputInjection and any app's `shim` (then the shim is not built); input membership defeats the uaccess isolation the shim backs.";
            }
            {
              # Base port must differ from the primary's (the bind loser loops in Restart=always).
              assertion = port != (config.services.sunshine.settings.port or 47989);
              message = "icedos.applications.sunshine-headless.session.sunshine.port (${toString port}) must differ from the primary sunshine instance's port (${
                toString (config.services.sunshine.settings.port or 47989)
              }) — two Sunshine daemons cannot share a TCP/UDP base port.";
            }
            {
              # openFirewall opens port+21 (RTSP); cap so it stays in NixOS' port range.
              assertion = port + 21 <= 65535;
              message = "icedos.applications.sunshine-headless.session.sunshine.port (${toString port}) must be <= 65514 because the openFirewall rule opens the derived port+21 (RTSP) block.";
            }
            {
              # These four select a patched gamescope/wrapper at build time, so an app can
              # only turn them ON when the module-global option built them. Off always works.
              assertion = lib.all (
                app:
                lib.all (k: app.gamescope.${k} != true || cfg.gamescope.${k}) [
                  "hdr"
                  "nativeWayland"
                  "inputInjection"
                  "mangoApp"
                ]
              ) cfg.apps;
              message = "icedos.applications.sunshine-headless.apps[].gamescope can only enable hdr/nativeWayland/inputInjection/mangoApp when the matching module-global gamescope.* option is also true (each selects a patched gamescope or wrapper at build time).";
            }
            {
              # Steam's environment is built at evaluation time from the module globals
              # (see steam-headless/hooks.nix), so a per-app value would be ignored there.
              assertion = lib.all (
                app: !app.steamMode || (app.gamescope.mangoApp == null && app.gamescope.nativeWayland == null)
              ) cfg.apps;
              message = "icedos.applications.sunshine-headless.apps[].gamescope.nativeWayland/mangoApp are ignored for a steamMode app: set the module-global gamescope value instead.";
            }
          ];

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

              # No namespacing or seccomp: a user namespace trips is_sandboxed() and gets a 503.
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

          # Tears the session down after session.idleTimeout, regrows the probe gamescope after
          # gamescope.regrowTimeout. Hardened like idle.service; it systemd-runs gamescope too.
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

          networking.firewall = mkIf cfg.session.sunshine.openFirewall headlessDaemon.firewall;
        }
      )
    ];

  meta = {
    name = "sunshine-headless";

    dependencies = [
      {
        modules = [
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
