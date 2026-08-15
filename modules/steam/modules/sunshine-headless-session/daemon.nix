# SECOND, INDEPENDENT Sunshine instance pinned to the private gamescope portal
# (gamescope-0 + private D-Bus), so it captures the headless session; the primary stays stock.
{
  pkgs,
  lib,
  cfg, # icedos.applications.steam.headless-session
  headlessSeat,
  # True when icedos.nix builds the input bridge (isolateVirtualControllers ||
  # steamOS || inputInjection): its wrapper exists then; otherwise use the plain binary.
  bridgeNeeded,
  sessionApp,
  steamApps,
}:

let
  inherit (cfg)
    autoStart
    name
    port
    ;

  # Headless apps for Sunshine. The top-level `env` node is REQUIRED: without it
  # Sunshine's parser aborts ("No such node (env)") and loads zero apps.
  appsJson = pkgs.writeText "sunshine-headless-apps.json" (
    builtins.toJSON {
      env = {
        PATH = "$(PATH):$(HOME)/.local/bin";
      };
      apps = steamApps;
    }
  );

  # Minimal config; state (pairing/certs/log) lands under the redirected XDG_CONFIG_HOME.
  # audio_sink = on-demand null-sink; system_tray=false (libnotify isn't on the private bus).
  sunshineConf = pkgs.writeText "sunshine-headless.conf" (''
    sunshine_name=${name}
    port=${toString port}
    capture=portal
    audio_sink=steam-sunshine-headless-sink
    system_tray=false
    file_apps=${appsJson}
  '');

  # Open the same port offsets the primary uses (relative to 47989), shifted to this base.
  firewall = {
    allowedTCPPorts = [
      (port - 5) # HTTPS
      port # HTTP
      (port + 1) # Web UI
      (port + 21) # RTSP
    ];
    allowedUDPPorts = [
      (port + 9) # Video
      (port + 10) # Control
      (port + 11) # Audio
      (port + 13) # Mic
      (port + 21) # same offset list as the nixpkgs sunshine module (UDP 48010 at the default base)
    ];
  };

  service = {
    description = "Sunshine (headless gamescope session) for Moonlight";
    wantedBy = lib.mkIf autoStart [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];

    # Pin to the private gamescope portal so this instance captures the headless
    # session; XDG_CONFIG_HOME is redirected to keep its state apart from the primary's.
    environment = {
      WAYLAND_DISPLAY = "gamescope-0";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=%t/sunshine-portal/bus";
      XDG_CONFIG_HOME = "%h/.config/sunshine-headless";
      # Always a non-seat0 seat: inputtino suffixes every device with the seat, so
      # gamescope's passthrough names match and the udev rules never touch the primary's pads.
      XDG_SEAT = headlessSeat;
    };

    # Gate on the idle gamescope + portal: Sunshine probes the display at startup
    # and never recovers (503); Restart=always retries a transient port-bind race.
    after = [
      "sunshine-headless-idle.service"
      "sunshine-portal.service"
    ];
    # wants both so the startup gate holds on the manual path too (After= alone is a no-op there).
    wants = [
      "sunshine-headless-idle.service"
      "sunshine-portal.service"
    ];

    serviceConfig = {
      ExecStartPre = [
        # The isolated state dir must exist before Sunshine writes its state
        # there (pairing, certs, log, portal_token).
        "${pkgs.coreutils}/bin/mkdir -p %h/.config/sunshine-headless/sunshine"
        # Drop a stale portal restore token so startup re-requests a fresh
        # ScreenCast instead of hanging on a dead session from a prior crash.
        "${pkgs.coreutils}/bin/rm -f %h/.config/sunshine-headless/sunshine/portal_token %h/.config/sunshine-headless/sunshine/portal_token.bak"
        (pkgs.writeShellScript "wait-gamescope" ''
          for _ in $(seq 1 200); do
            [ -S "$XDG_RUNTIME_DIR/gamescope-0" ] && exit 0
            sleep 0.05
          done
          echo "timeout waiting for gamescope-0" >&2
          exit 1
        '')
      ];
      # ROOT shim (only when the bridge is built): daemon needs `input` for its pads
      # but must keep the caller's gids — a gid-`input` process fails the portal's /proc/<pid>/root check (503).
      ExecStart =
        (lib.optionalString bridgeNeeded "/run/wrappers/bin/sunshine-headless-gid-root ")
        + "${pkgs.sunshine}/bin/sunshine ${sunshineConf}";
      Restart = "always";
      RestartSec = "3s";
      # Cap the stop: Sunshine's SIGTERM watchdog hangs ~10s then leaks its portal
      # session; SIGKILL + clean D-Bus disconnect lets the portal reap it fast.
      TimeoutStopSec = "5s";
      # SIGKILL skips Sunshine's sink undo; release just the audio half here
      # (cleanup, not stop — a crash-restart mid-game must not kill the session).
      ExecStopPost = "${lib.getExe sessionApp} cleanup";

      # No namespacing/NoNewPrivileges: the tree execs setgid/setuid wrappers, which
      # NNP or any user namespace would strip (and the portal would deny /proc/<pid>/root).
      UMask = "0027";
    };
    unitConfig.StartLimitIntervalSec = 0;
  };
in
{
  inherit service firewall;
}
