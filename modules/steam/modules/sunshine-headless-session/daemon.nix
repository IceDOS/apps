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
    # Stream to Vulkan Video (RADV) directly: skips the futile nvenc probe and its
    # libcuda/CUDA noise on AMD-only rigs.
    encoder=vulkan
    # Low Latency tune: reduces encoding delay at the cost of peak quality.
    vk_tune=2
    audio_sink=steam-sunshine-headless-sink
    system_tray=false
    file_apps=${appsJson}
  '');

  # Post-start: confirm the configured encoder actually initialized and surface the selected
  # encoder + GPU in the journal, so a dead stream has a root cause. Best-effort, exits 0.
  encoderDiag = pkgs.writeShellScript "sunshine-headless-encoder-diag" ''
    # Same XDG_CONFIG_HOME the unit exports, so the path tracks a config redirect.
    log="''${XDG_CONFIG_HOME:-$HOME/.config/sunshine-headless}/sunshine/sunshine.log"
    # ExecStartPost can beat Sunshine's first log creation on a cold start; give it a moment.
    for _ in $(seq 1 20); do [ -f "$log" ] && break; sleep 0.1; done
    [ -f "$log" ] || { echo "sunshine-headless-encoder: no log at $log" >&2; exit 0; }
    start="$(stat -c %s "$log" 2>/dev/null || echo 0)"
    # Wait for this boot's H.264 outcome (Found or failed init); HEVC's line can land first and would mislead the warning.
    fresh=""
    h264_done=""
    for _ in $(seq 1 80); do
      size="$(stat -c %s "$log" 2>/dev/null || echo 0)"
      [ "$size" -gt "$start" ] || { sleep 0.1; continue; }
      fresh="$(tail -c +$((start + 1)) "$log" 2>/dev/null || true)"
      if printf '%s\n' "$fresh" | grep -qE 'Found H\.264 encoder:|Could not open codec \[h264_vulkan\]'; then
        h264_done=1
        break
      fi
      sleep 0.1
    done
    # Late start or H.264 line never within 8s: use the newest block in the file.
    if [ -z "$h264_done" ]; then
      fresh="$(tail -n 200 "$log" 2>/dev/null || true)"
    fi
    printf '%s\n' "$fresh" | grep -E "config: 'encoder' =|Found (H\.264|HEVC) encoder:|Vulkan encode using GPU:" \
      | sed -E 's/^\[[^]]*\]: (Info|Warning|Error): //' \
      | sed 's/^/sunshine-headless-encoder: /'
    cfg_enc="$(printf '%s\n' "$fresh" | sed -nE "s/^.*config: 'encoder' = ([a-z0-9_]+).*/\1/p" | tail -n1)"
    if [ "$cfg_enc" = vulkan ] && ! printf '%s\n' "$fresh" | grep -q 'Found H\.264 encoder: .*\[vulkan\]'; then
      echo "sunshine-headless-encoder: WARNING configured encoder=vulkan but no Vulkan H.264 encoder was found; streaming may fail. Consider encoder=vaapi." >&2
    fi
    exit 0
  '';

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
      # Post-start: surface the selected encoder / GPU and warn if vulkan init failed.
      ExecStartPost = "${encoderDiag}";
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
    unitConfig = {
      # Bounded restart window: a persistent failure (e.g. a port collision) must not loop
      # in `/bin/false` every 3s forever; systemd backoffs after StartLimitBurst tries.
      StartLimitIntervalSec = 300;
      StartLimitBurst = 10;
    };
  };
in
{
  inherit service firewall;
}
