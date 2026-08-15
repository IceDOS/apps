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

          inherit (lib) mkIf;

          inherit (cfg)
            excludeHostControllers
            inputInjection
            isolateVirtualControllers
            port
            secondarySteamSession
            secondarySteamSessionPath
            steamOS
            ;

          # Non-seat0 seat so inputtino suffixes every device with it: the patched
          # gamescope matches the passthrough names and the udev rules stay scoped to this instance.
          headlessSeat = "seat-headless";

          # One flag gates the input bridge (wrapper, marker group, membership
          # assertion) so the three can't drift apart.
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
        in
        {
          # The whole block below is the HEADLESS session; the primary is untouched.

          # Strip uaccess from the headless pads (seat-suffixed glob, priority 72):
          # host desktop can't open them, the injected Steam can via the shim.
          services.udev.packages =
            lib.optional isolateVirtualControllers (
              pkgs.writeTextDir "etc/udev/rules.d/72-sunshine-headless-no-uaccess.rules" ''
                SUBSYSTEM=="input", ATTRS{name}=="Sunshine* (${headlessSeat})*", TAG-="uaccess", MODE="0660", RUN+="${pkgs.acl}/bin/setfacl -b $env{DEVNAME}"
              ''
            )
            # Strip uaccess from inputInjection's passthrough devices too (gamescope's
            # EVIOCGRAB alone leaks input to the desktop in the ungrabbed window).
            ++ lib.optional inputInjection (
              pkgs.writeTextDir "etc/udev/rules.d/72-sunshine-headless-input-no-uaccess.rules" ''
                SUBSYSTEM=="input", ATTRS{name}=="*passthrough (${headlessSeat})*", TAG-="uaccess", MODE="0660", RUN+="${pkgs.acl}/bin/setfacl -b $env{DEVNAME}"
              ''
            )
            # -steamos3 Steam opens /dev/rfkill O_RDWR; hand the node to `input` (no
            # human members) so only the shim-promoted Steam gets radio control. Priority 70.
            ++ lib.optional steamOS (
              pkgs.writeTextDir "etc/udev/rules.d/70-steam-rfkill-access.rules" ''
                SUBSYSTEM=="misc", KERNEL=="rfkill", GROUP="input", MODE="0660"
              ''
            );

          # setgid-`input` shim: gives the injected Steam / patched gamescope `input`
          # access (pads, rfkill, passthrough); caller gate = root or marker-group member.
          security.wrappers = mkIf bridgeNeeded {
            # Mode A (setgid `input`): gamescope + injected Steam get real gid `input`.
            # The daemon must NOT use it (gid-`input` fails the portal's /proc/<pid>/root check -> 503).
            sunshine-headless-gid = {
              setgid = true;
              owner = "root";
              group = "input";
              source = "${gidExec}";
            };
            # Mode B (setuid `root`, daemon only): keeps the caller's gids, adds `input`
            # as supplementary, drops root. Group = marker, no o+x: kernel enforces the gate.
            sunshine-headless-gid-root = {
              setuid = true;
              owner = "root";
              group = inputBridgeGroup;
              permissions = "u+rx,g+x";
              source = "${gidExec}";
            };
          };

          # Marker group the shim's caller gate checks; grants nothing by itself —
          # only executing the wrapper turns it into `input` access.
          users.groups = mkIf bridgeNeeded {
            ${inputBridgeGroup} = { };
          };

          users.users = mkIf bridgeNeeded (
            icedosLib.users.mkGroupInjector inputBridgeGroup (config.icedos.users)
          );

          # -steamos3 Steam needs InputPlumber for controller ordering/routing.
          services.inputplumber.enable = mkIf steamOS true;

          # Let the active local session manage the injected-Steam scope without sudo.
          security.polkit.extraConfig = mkIf excludeHostControllers ''
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
              # The shim's security model: `input` has no human members. Assert on the
              # effective membership of normal users — any voids the caller gate.
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
              # The two daemons must not share a base port (the bind loser exits 0 into
              # the Restart=always loop). Compare against the primary's configured port.
              assertion = port != (config.services.sunshine.settings.port or 47989);
              message = "icedos.applications.steam.headless-session.port (${toString port}) must differ from the primary sunshine instance's port (${
                toString (config.services.sunshine.settings.port or 47989)
              }) — two Sunshine daemons cannot share a TCP/UDP base port.";
            }
            {
              # openFirewall opens the derived port+21 (RTSP) block; cap the base so
              # that stays inside NixOS' port range instead of failing opaquely.
              assertion = port + 21 <= 65535;
              message = "icedos.applications.steam.headless-session.port (${toString port}) must be <= 65514 because the openFirewall rule opens the derived port+21 (RTSP) block.";
            }
          ];

          # Rename steamwebhelper's PulseAudio app: WirePlumber otherwise saves its route
          # under the shared "Chromium" key and poisons desktop Chromium apps (Signal).
          services.pipewire.extraConfig.pipewire-pulse."90-steam-headless-audio-name" = {
            "pulse.rules" = [
              {
                matches = [ { "application.process.binary" = "steamwebhelper"; } ];
                actions.update-props."application.name" = "Steam";
              }
            ];
          };

          # Private D-Bus + portal frontend so gamescope's ScreenCast never touches the
          # host portal and only the headless daemon consumes its pipewire node.
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

              # No namespacing/seccomp: for an unprivileged user-manager unit they imply a
              # user namespace, which breaks the portal checks — the stack stays unnamespaced.
              UMask = "0027";
            };
          };

          systemd.user.services.sunshine-portal = {
            description = "Private xdg-desktop-portal (gamescope) for Sunshine headless";
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            requires = [ "sunshine-portal-bus.service" ];

            # After bus ONLY (ordering after idle + target membership would cycle);
            # the backend is D-Bus-activated lazily.
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

              # No namespacing/seccomp: they imply a user namespace, and the portal's
              # is_sandboxed() check then denies /proc/<pid>/root -> ScreenCast denied (503).
              UMask = "0027";
            };
          };

          # Boot-time idle gamescope: Sunshine probes the display at stream launch,
          # before its prep-cmd would spawn gamescope — a display must already exist.
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

          # The headless daemon: a SECOND, independent Sunshine instance pinned to the
          # private gamescope portal — own ports, own isolated state, captures gamescope-0.
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
