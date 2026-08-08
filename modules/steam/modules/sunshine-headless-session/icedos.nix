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

          inherit (lib) mkDefault mkIf;

          inherit (cfg)
            excludeHostControllers
            inputInjection
            isolateVirtualControllers
            secondarySteamSession
            secondarySteamSessionPath
            steamOS
            ;

          # Seat under which the primary Sunshine's inputtino devices are created
          # (inputInjection). A non-seat0 XDG_SEAT makes inputtino suffix every
          # device name with the seat; the patched gamescope matches those exact
          # names. The desktop-capture instance leaves the seat unset → plain
          # names, so the two Sunshine instances' devices never collide.
          headlessSeat = "seat-headless";

          # The setgid-`input` shim is needed for all three modes: the injected
          # Steam (isolateVirtualControllers, steamOS) and the patched gamescope
          # (inputInjection). One flag gates the wrapper, the marker group and
          # the membership assertion below so they can't drift apart.
          bridgeNeeded = isolateVirtualControllers || steamOS || inputInjection;

          packages = import ./packages.nix {
            inherit
              pkgs
              lib
              inputs
              cfg
              ;

            steamPkg = ((import ../../lib/resolved-steam.nix) { inherit config pkgs; }).resolved;
          };

          inherit (packages)
            xdg-desktop-portal-gamescope
            sunshinePortalConfig
            gidExec
            inputBridgeGroup
            ;

          inherit
            (import ./scripts.nix {
              inherit pkgs lib cfg;
              inherit headlessSeat;
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
            cfg = cfg.desktop-capture;
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
            # inputInjection's keyboard/mouse passthrough devices ("Keyboard passthrough
            # (seat-headless)", "Mouse passthrough (seat-headless)", "Mouse passthrough
            # (seat-headless) (absolute)") are NOT covered by the Sunshine* pad rule above and
            # rely only on gamescope's EVIOCGRAB — in the ungrabbed window (device created
            # before gamescope grabs it, or gamescope down/restarting) the host desktop (not in
            # `input`) still holds a seat0 uaccess ACL and client input leaks into the desktop.
            # Strip it like the pad; the patched gamescope still opens the nodes via the
            # setgid-`input` shim. Distinct filename so two udev package derivations don't
            # collide when both features are on. The (seat-headless) glob only matches the
            # inputInjection instance's seat-suffixed names — the desktop-capture instance (no
            # XDG_SEAT) keeps its plain-named devices open for the real desktop.
            ++ lib.optional inputInjection (
              pkgs.writeTextDir "etc/udev/rules.d/72-sunshine-headless-input-no-uaccess.rules" ''
                SUBSYSTEM=="input", ATTRS{name}=="*passthrough (${headlessSeat})*", TAG-="uaccess", MODE="0660", RUN+="${pkgs.acl}/bin/setfacl -b $env{DEVNAME}"
              ''
            )
            # Steam's Deck UI (-steamos3) opens /dev/rfkill O_RDWR to read/monitor/control
            # the radios. Default perms are root:root 0664 → read-only for a non-active-seat
            # user; systemd's 70-uaccess.rules grants rw only to the ACTIVE seat session, so a
            # headless / boot-time -steamos3 Steam has no ACL → its O_RDWR open fails → it
            # force-disables Bluetooth and its radio UI desyncs from the system.
            # Hand rfkill to the `input` GROUP (not `users`): that group has NO human members
            # (the assertion below rejects any normal user in `input`), so ONLY the injected
            # Steam — which the setgid-`input` shim runs as real gid
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

          # setgid-`input` shim: the injected Steam (execs through it) gets the
          # `input` group — needed to open the uaccess-stripped pad
          # (isolateVirtualControllers) AND the input-group /dev/rfkill node under
          # -steamos3 (radio access); inputInjection's patched gamescope also execs
          # through it so it can open the inputtino passthrough devices (the user
          # is not in `input`). Built for any of the three. Access is gated on the
          # caller being root or a member of the `sunshine-headless` marker group
          # (below) — every IceDOS user is a member, so all users of this feature
          # work without per-user config; the `input` group itself keeps NO human
          # members, so the wrapper stays the only path to it (the assertion
          # below hard-fails the build if a normal user ever lands in `input`
          # by any route, keeping this invariant true).
          security.wrappers = mkIf bridgeNeeded {
            sunshine-headless-gid = {
              setgid = true;
              owner = "root";
              group = "input";
              source = "${gidExec}";
            };
          };

          # The marker group the shim checks: the wrapper's own gate. Grants
          # nothing by itself (no kernel rights, `input` membership untouched) —
          # only executing the wrapper turns it into gid `input`. Adding every
          # IceDOS user via `users.users` merges with core's extraGroups assembly
          # (users.nix) per user.
          users.groups = mkIf bridgeNeeded {
            ${inputBridgeGroup} = { };
          };

          users.users = mkIf bridgeNeeded (
            icedosLib.users.mkGroupInjector inputBridgeGroup (config.icedos.users)
          );

          # Steam in -steamos3 mode expects InputPlumber for controller ordering and
          # input routing (composite devices, D-Bus API). Without it the Controller Order
          # UI in Settings is hidden entirely.
          services.inputplumber.enable = mkIf steamOS true;

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
              message = "icedos.applications.steam.headless-session.secondarySteamSessionPath must be set (non-empty) when secondarySteamSession is enabled.";
            }
            {
              assertion =
                !(cfg.desktop-capture.enable && cfg.desktop-capture.backend == "kms")
                || config.icedos.applications.sunshine.capSysAdmin;
              message = "icedos.applications.steam.headless-session.desktop-capture.backend = \"kms\" requires icedos.applications.sunshine.capSysAdmin = true (the setcap wrapper Sunshine needs for raw KMS/DRM capture).";
            }
            {
              # The shim's security model is that `input` has no human members
              # (only the wrapper bridges to it). Assert on the effective
              # membership of HUMAN accounts, covering every way a normal user
              # can land in `input`: extraGroups (the input-remapper module
              # injects every user via mkGroupInjector, and a hand-written
              # icedos.users.<name>.extraGroups = ["input"] does the same
              # directly), a primary group, or users.groups.input.members —
              # all void the caller gate and the uaccess isolation this backs.
              # System/service accounts (e.g. evdevremapkeys' daemon user) are
              # excluded: they have no login session, so they can't bridge to
              # the shim's caller gate.
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
          ];

          services.sunshine.settings.audio_sink = mkDefault "steam-sunshine-headless-sink";
          services.sunshine.settings.capture = mkDefault "portal";

          # Tray libnotify calls org.freedesktop.Notifications, which isn't on the
          # private portal bus → SIGTRAP → Sunshine core-dumps mid-stream. Disable it.
          services.sunshine.settings.system_tray = mkDefault false;

          # signal-desktop (and any bare-"Chromium" Electron app) shares the generic
          # PulseAudio application.name "Chromium" with the injected Steam's CEF
          # steamwebhelper. Each session route_session_audio (scripts.nix) moves the
          # webhelper's audio onto the capture sink, and WirePlumber persists that as the
          # saved restore-target for the "Chromium" key — so a desktop Chromium app (Signal)
          # then inherits it and is pinned to the stream sink instead of the speakers, even
          # while the system default is the real device. Rename the webhelper's audio so the
          # session writes its OWN restore key ("Steam") and never poisons the shared
          # "Chromium" one; helium etc. self-name and were never affected. Routing is
          # unaffected — route_session_audio matches by PID and Sunshine captures the sink
          # monitor regardless of client name. Must be a server-side rule: CEF sets
          # application.name itself, and env (PULSE_PROP*) can't override an app-set prop.
          services.pipewire.extraConfig.pipewire-pulse."90-steam-headless-audio-name" = {
            "pulse.rules" = [
              {
                matches = [ { "application.process.binary" = "steamwebhelper"; } ];
                actions.update-props."application.name" = "Steam";
              }
            ];
          };

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

              # NO namespacing/seccomp hardening (only UMask): for an unprivileged
              # user-manager unit ANY namespace (PrivateTmp/Protect*) or seccomp
              # (Restrict*) option implies a user namespace (PrivateUsers
              # self-mapping). D-Bus-activated services inherit the bus daemon's
              # namespace, so a namespaced bus drags the gamescope backend + the
              # document portal into the namespace too — same breakage as the
              # sunshine-portal unit below (portal is_sandboxed caller check, fuse
              # mount). The whole private stack must stay unnamespaced.
              UMask = "0027";
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

              # NO namespacing/seccomp hardening (only UMask): for an unprivileged
              # user-manager unit ANY namespace (PrivateTmp/Protect*) or seccomp
              # (Restrict*) option implies a user namespace (PrivateUsers
              # self-mapping). The portal's own is_sandboxed() caller check opens
              # /proc/<sunshine-pid>/root to detect sandboxed apps; across the
              # user-namespace boundary that open fails with EACCES, so the portal
              # treats the unnamespaced Sunshine as sandboxed and denies ScreenCast
              # ("Portal operation not allowed: Unable to open /proc/PID/root") —
              # Sunshine then finds no display at startup and every Moonlight
              # connect fails with 503.
              UMask = "0027";
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
            }
            # inputInjection: create this instance's inputtino devices under a
            # non-seat0 name so they (a) get the seat-suffixed names the patched
            # gamescope matches and (b) never collide with the desktop-capture
            # instance's plain-named devices.
            #
            # NB: NixOS activation does NOT restart running user services. When
            # inputInjection is toggled, gamescope restarts itself on the next
            # stream via the gamescope_marker fingerprint, but a still-running
            # Sunshine would keep creating plain-named inputtino devices the new
            # gamescope never matches (injection silently no-ops until the next
            # login). Restart it: systemctl --user restart sunshine.
            // lib.optionalAttrs inputInjection { XDG_SEAT = headlessSeat; };
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
              # Sunshine normally unloads the stream sink via `stop` (its apps.nix undo), but
              # the SIGKILL above means that never runs → the null-sink stays default and mutes
              # the desktop until relogin. ExecStopPost releases just the audio half (`cleanup`,
              # not `stop` — a crash-restart while a game is up must not kill the session).
              ExecStopPost = "${lib.getExe sessionApp} cleanup";

              # This unit's process tree execs privilege-bearing wrappers, so it
              # cannot take namespacing or NoNewPrivileges: the prep-cmd chain
              # runs the injected Steam through the setgid-`input` shim
              # (/run/wrappers/bin/sunshine-headless-gid — isolateVirtualControllers
              # / steamOS, for the pad + /dev/rfkill) and, under capSysAdmin
              # (mandatory for the kms backend), Sunshine itself runs as the
              # setcap wrapper (/run/wrappers/bin/sunshine). NoNewPrivileges
              # strips both the setgid bit and file capabilities at exec, and
              # for an unprivileged user-manager unit ANY namespace or seccomp
              # option implies a user namespace (PrivateUsers self-mapping),
              # inside which file capabilities and setuid/setgid are ignored
              # regardless — so this unit keeps only UMask. sunshine-headless-idle
              # keeps the full seccomp + namespace set (it only spawns gamescope
              # via systemd-run, whose transient unit is unnamespaced anyway), but
              # sunshine-portal-bus and -portal must ALSO stay unnamespaced: the
              # portal's is_sandboxed() caller check cannot open /proc/<pid>/root
              # across a user-namespace boundary, which denies every Sunshine
              # ScreenCast (503).
              UMask = "0027";
            };
            unitConfig.StartLimitIntervalSec = lib.mkForce 0;
          };

          # Second, independent Sunshine instance for the REAL physical desktop (see
          # desktop-capture.nix). Kept entirely separate from the gamescope-pinned primary:
          # its own ports, its own isolated state/pairing, and it inherits the real Plasma
          # Wayland session (so capture=portal → KWin ScreenCast) instead of gamescope-0.
          systemd.user.services.sunshine-desktop = mkIf cfg.desktop-capture.enable desktopCapture.service;

          networking.firewall = mkIf (
            cfg.desktop-capture.enable && cfg.desktop-capture.openFirewall
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
