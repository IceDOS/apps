# SECOND, independent Sunshine instance pinned to the private gamescope portal
# (gamescope-0 + private D-Bus); the primary stays stock.
{
  pkgs,
  lib,
  cfg, # icedos.applications.steam.headless-session
  headlessSeat,
  # Use the shim wrapper only when icedos.nix builds the input bridge; else plain binary.
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

  # The top-level `env` node is REQUIRED: without it Sunshine's parser aborts.
  appsJson = pkgs.writeText "sunshine-headless-apps.json" (
    builtins.toJSON {
      env = {
        PATH = "$(PATH):$(HOME)/.local/bin";
      };
      apps = steamApps;
    }
  );

  # Minimal config; state lands under the redirected XDG_CONFIG_HOME.
  # audio_sink = null-sink; system_tray = false (no libnotify on the private bus).
  sunshineConf = pkgs.writeText "sunshine-headless.conf" (''
    sunshine_name=${name}
    port=${toString port}
    capture=portal
    audio_sink=steam-sunshine-headless-sink
    system_tray=false
    file_apps=${appsJson}
  '');

  # Same port offsets as the primary (relative to 47989), shifted to this base.
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

    # Pin to the private portal so this instance captures the headless session;
    # XDG_CONFIG_HOME redirected to keep state apart from the primary.
    environment = {
      WAYLAND_DISPLAY = "gamescope-0";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=%t/sunshine-portal/bus";
      XDG_CONFIG_HOME = "%h/.config/sunshine-headless";
      # Non-seat0 seat: inputtino suffixes devices with it; udev rules never touch the primary's pads.
      XDG_SEAT = headlessSeat;
    };

    # Gate on idle gamescope + portal: Sunshine's display probe never recovers (503).
    after = [
      "sunshine-headless-idle.service"
      "sunshine-portal.service"
    ];
    # Wants both so the gate holds on the manual path too (After= alone is a no-op).
    wants = [
      "sunshine-headless-idle.service"
      "sunshine-portal.service"
    ];

    serviceConfig = {
      ExecStartPre = [
        # State dir must exist before Sunshine writes (pairing, certs, log, portal_token).
        "${pkgs.coreutils}/bin/mkdir -p %h/.config/sunshine-headless/sunshine"
        # Drop a stale portal token so startup re-requests a fresh ScreenCast.
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
      # ROOT shim: daemon needs `input` but must keep caller gids (gid-`input` fails
      # the portal's /proc/<pid>/root check -> 503).
      ExecStart =
        (lib.optionalString bridgeNeeded "/run/wrappers/bin/sunshine-headless-gid-root ")
        + "${pkgs.sunshine}/bin/sunshine ${sunshineConf}";
      Restart = "always";
      RestartSec = "3s";
      # SIGKILL + clean D-Bus disconnect: the SIGTERM watchdog hangs ~10s and leaks the portal session.
      TimeoutStopSec = "5s";
      # SIGKILL skips sink undo; release just the audio half (cleanup, not stop).
      ExecStopPost = "${lib.getExe sessionApp} cleanup";

      # No namespacing/NNP: the tree execs setgid/setuid wrappers (and the portal
      # would deny /proc/<pid>/root).
      UMask = "0027";
    };
    unitConfig.StartLimitIntervalSec = 0;
  };
in
{
  inherit service firewall;
}
