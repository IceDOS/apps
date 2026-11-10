{
  config,
  icedosLib,
  lib,
  ...
}:

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

          isolateVirtualControllers = cfg.session.controllers.isolateVirtual;
          port = cfg.session.sunshine.port;

          compositors = cfg.compositors;

          defaultCompositor =
            if cfg.session.defaultCompositor != "" then
              cfg.session.defaultCompositor
            else if compositors ? gamescope then
              "gamescope"
            else if compositors != { } then
              lib.head (lib.attrNames compositors)
            else
              "";

          inputInjection = lib.any (c: c.inputBridge) (lib.attrValues compositors);

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
              compositor = if app.compositor != "" then app.compositor else defaultCompositor;
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
            inherit pkgs lib;
            sunshinePkg = pkgs.sunshine;
            steamVersion = pkgs.steam.version or "0";
          };

          inherit (packages)
            gidExec
            inputBridgeGroup
            ;

          inherit
            (import ./scripts.nix {
              inherit
                pkgs
                lib
                cfg
                apps
                compositors
                defaultCompositor
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
              bridgeNeeded
              sessionApp
              compositors
              defaultCompositor
              ;

            apps = sunshineApps;
          };

          # Custom session.conf: standard servicedirs + the backend portal's D-Bus service dir,
          # so dbus-daemon can D-Bus-activate org.freedesktop.impl.portal.desktop.<name>.
          portalBusConf =
            name: serviceDirs:
            pkgs.writeText "sunshine-portal-bus-${name}.conf" ''
              <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
               "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
              <busconfig>
                <type>session</type>
                <keep_umask/>
                <auth>EXTERNAL</auth>
                <!-- config-file mode makes dbus-daemon require a listen element here;
                     the unit passes address= on the command line, which overrides it. -->
                <listen>unix:tmpdir=/tmp</listen>
                <!-- The first file for a name wins, so backend dirs can override system services. -->
                ${lib.concatMapStrings (d: "<servicedir>${d}</servicedir>\n") serviceDirs}
                <standard_session_servicedirs />
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

          mkPortalUnits =
            name: c:
            let
              address = "unix:path=%t/sunshine-portal/${name}/bus";
            in
            {
              "sunshine-portal-bus-${name}" = {
                description = "Private D-Bus for the Sunshine headless ${name} portal";
                wantedBy = [ "graphical-session.target" ];
                partOf = [ "graphical-session.target" ];
                environment = c.portal.busEnvironment;
                serviceConfig = {
                  ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %t/sunshine-portal/${name}/data";
                  ExecStart = "${pkgs.dbus}/bin/dbus-daemon --nofork --nopidfile --address=${address} --config-file=${portalBusConf name c.portal.serviceDirs}";
                  Restart = "always";
                  RestartSec = "2s";
                  # No namespacing or seccomp: a user namespace breaks the portal checks.
                  UMask = "0027";
                };
              };

              "sunshine-portal-${name}" = {
                description = "Private xdg-desktop-portal (${name}) for Sunshine headless";
                wantedBy = lib.mkIf c.portal.autoStart [ "graphical-session.target" ];
                partOf = [ "graphical-session.target" ];
                requires = [ "sunshine-portal-bus-${name}.service" ];
                after = [ "sunshine-portal-bus-${name}.service" ];
                environment = c.portal.environment // {
                  DBUS_SESSION_BUS_ADDRESS = address;
                };
                serviceConfig = {
                  ExecStart = "${pkgs.xdg-desktop-portal}/libexec/xdg-desktop-portal --verbose";
                  Restart = "always";
                  RestartSec = "2s";
                  # No namespacing or seccomp: a user namespace trips is_sandboxed() and gets a 503.
                  UMask = "0027";
                };
              };
            };
        in
        {
          # Backport of Sunshine #6044. mkBefore: this must run before the sunshine module's symlinkJoin overlay.
          nixpkgs.overlays = lib.mkBefore [
            (_: previous: {
              sunshine = previous.sunshine.overrideAttrs (old: {
                patches = (old.patches or [ ]) ++ [ ./lib/portalgrab-subscribe-first.patch ];
              });
            })
          ];

          # The whole block below is the HEADLESS session; the primary is untouched.

          # xpadneo binds Sunshine's emulated pad whenever it advertises an Xbox VID/PID (every
          # uhid pad type here does), and its hidraw node then reports nothing, so hidraw-only
          # games see no input. hid-generic cannot take the device once xpadneo is gone, so with
          # xpadneo loaded the only working pad is `generic`, which stays on uinput and never
          # reaches the HID bus. mkDefault, so an explicit gamepad in config.toml still wins.
          icedos.applications.sunshine-headless.session.sunshine.gamepad = lib.mkIf (
            config.hardware.xpadneo.enable
            || lib.any (mod: lib.hasPrefix "hid_xpadneo" mod) config.boot.kernelModules
          ) (lib.mkDefault "generic");

          # Strip uaccess from Sunshine's pads (priority 72; also hits the primary daemon's): only a
          # shim-promoted app can open them (group `input` has no human members).
          services.udev.packages =
            lib.optional isolateVirtualControllers (
              pkgs.writeTextDir "etc/udev/rules.d/72-sunshine-headless-no-uaccess.rules" ''
                SUBSYSTEM=="input", ATTRS{name}=="Sunshine *", TAG-="uaccess", MODE="0660", RUN+="${pkgs.acl}/bin/setfacl -b $env{DEVNAME}"
              ''
            )
            # Same for inputInjection's keyboard/mouse devices (EVIOCGRAB alone leaks input).
            ++ lib.optional inputInjection (
              pkgs.writeTextDir "etc/udev/rules.d/72-sunshine-headless-input-no-uaccess.rules" ''
                SUBSYSTEM=="input", ATTRS{name}=="libvirtualhid *", TAG-="uaccess", MODE="0660", RUN+="${pkgs.acl}/bin/setfacl -b $env{DEVNAME}"
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
                    SUBSYSTEM=="input", ATTRS{name}=="Sunshine *", RUN+="${lib.getExe sessionApp} refresh"
                    SUBSYSTEM=="input", ATTRS{name}=="libvirtualhid *", RUN+="${lib.getExe sessionApp} refresh"
                    # A hidraw node has no ATTRS{name} (the HID device keeps the name in
                    # HID_NAME), so match on the subsystem and let refresh filter.
                    SUBSYSTEM=="hidraw", RUN+="${lib.getExe sessionApp} refresh"
                  ''
                );

          # The gid shim's setgid exec clears ambient caps, so CAP_SYS_NICE has to come from
          # a wrapper the shim execs. Always registered; gamescope needs it for SetNice and --rt.
          security.wrappers = mkIf bridgeNeeded {
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
          };

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
              assertion = apps == [ ] || compositors != { };
              message = "icedos.applications.sunshine-headless.apps needs a compositor backend module, such as sunshine-headless-gamescope from github:icedos/gaming.";
            }
            {
              assertion = lib.all (app: compositors ? ${app.compositor}) apps;
              message = "icedos.applications.sunshine-headless.apps[].compositor must name a registered backend (${lib.concatStringsSep ", " (lib.attrNames compositors)}).";
            }
          ];

          systemd.user.services = lib.mkMerge (
            (lib.mapAttrsToList mkPortalUnits compositors)
            ++ [
              {
                # Boot-time idle gamescope: Sunshine's display probe needs one before prep-cmd spawns it.
                sunshine-headless-idle = {
                  description = "Boot-time idle gamescope so Sunshine's display probe passes";
                  wantedBy = [ "graphical-session.target" ];
                  partOf = [ "graphical-session.target" ];
                  # A switch that restarts PipeWire must finish that first, or the stale-probe check misses it.
                  after = [ "pipewire.service" ];

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
                sunshine-headless-recycle = {
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

                # The headless daemon: a second, independent Sunshine pinned to the private portal.
                sunshine-headless = headlessDaemon.service;
              }
            ]
          );

          systemd.user.timers.sunshine-headless-recycle = {
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            timerConfig = {
              Unit = "sunshine-headless-recycle.service";
              OnBootSec = "1min";
              OnUnitActiveSec = "30s";
            };
          };

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
    ];
  };
}
