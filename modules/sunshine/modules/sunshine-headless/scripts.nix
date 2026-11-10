# Runtime shell: the generic per-app session helper and compositor dispatch.
# Apps come from icedos.applications.sunshine-headless.apps and supply shell hooks;
# scripts.nix dispatches app_<slug>_<hook> and falls back to default_app_<hook>.
{
  pkgs,
  lib,
  cfg,
  apps,
  compositors,
  defaultCompositor,
}:

let
  inherit (pkgs) writeShellApplication;

  inherit (cfg) session;

  isolateVirtualControllers = session.controllers.isolateVirtual;
  sessionIdleTimeout = session.idleTimeout;

  sinkName = "sunshine-headless-sink";
  # One pulse property string; built here so a quote in the name cannot break the shell word.
  sinkProperties = "node.description=\"${session.sunshine.name} (headless)\"";

  # excludeHostControllers allowlist: scope denies everything not listed;
  # the stream's pads are allowed per-device in `wait`.
  deviceAllowBase = [
    "char-drm rwm" # GPU (/dev/dri/card*, renderD*)
    "/dev/dri rwm"
    "/dev/uinput rwm" # Steam Input creates its own virtual pad
    "char-snd rwm" # ALSA (most audio is via the pipewire socket, but be safe)
    "char-pts rwm"
    "/dev/ptmx rwm"
    "/dev/tty rwm"
    "/dev/fuse rwm" # some compat tools
  ];

  deviceAllowRunArgs = lib.concatMapStringsSep " " (a: "-p DeviceAllow='${a}'") deviceAllowBase;
  deviceAllowSetArgs = lib.concatMapStringsSep " " (a: "DeviceAllow='${a}'") deviceAllowBase;

  # The helper records the new session's pgid and execs `command`, so an app needs no
  # launcher wrapper (see pgRecord).
  appCmdLine = app: "app_cmd=(${lib.concatMapStringsSep " " lib.escapeShellArg app.command})";

  # Per-app env: values are exported for the launched app; an empty value moves the
  # variable to the unset list (e.g. forcing X11 by dropping WAYLAND_DISPLAY).
  appEnvLine =
    app:
    lib.concatStrings (
      lib.mapAttrsToList (
        k: v:
        if v == "" then
          "      app_unset_env+=(${lib.escapeShellArg k})\n"
        else
          "      app_env+=(${lib.escapeShellArg "${k}=${toString v}"})\n"
      ) app.env
    );

  # Bash to run the pgid recorder with (writeShellApplication's runtimeInputs has no bash).
  pgShell = "${pkgs.bash}/bin/bash";

  # Records the new session's pgid (its own pid, see setsid/systemd-run below) and then execs
  # the payload in place, so `wait`/`stop` match the app's whole process group. A file rather
  # than a quoted string, so nothing has to escape the `$$` and `$@` it must keep unexpanded.
  pgRecord = pkgs.writeText "sunshine-headless-pg-record.sh" ''
    printf "%s" "$$" >"$SUNSHINE_HEADLESS_PGID"
    exec "$@"
  '';

  hookNames = [
    "start"
    "alive"
    "pids"
    "tick"
    "stop"
    "drain"
  ];

  # App hooks: an app defines only what it needs; an empty hook falls back to default_app_<hook>.
  hookFunctions = lib.concatMapStrings (
    app:
    lib.concatMapStrings (
      hook:
      lib.optionalString (app.hooks.${hook} != "") ''
        app_${app.slug}_${hook}() {
        ${app.hooks.${hook}}
        }
      ''
    ) hookNames
  ) apps;

  # One case arm per app: name is the lookup key, slug drives every runtime path.
  appCases = lib.concatMapStrings (app: ''
    ${lib.escapeShellArg app.name} | ${lib.escapeShellArg "sunshine-headless-${app.slug}.scope"})
      app_name=${lib.escapeShellArg app.name}
      app_slug=${lib.escapeShellArg app.slug}
      app_home=${lib.escapeShellArg app.home}
      app_compositor=${lib.escapeShellArg app.compositor}
      app_shim=${if app.shim then "1" else "0"}
      app_s_idle=${toString app.session.idleTimeout}
      app_s_pause=${if app.session.pauseOnDisconnect then "1" else "0"}
      app_s_exclude_host=${if app.session.controllers.excludeHost then "1" else "0"}
      ${appCmdLine app}
      ${appEnvLine app}
      ;;
  '') apps;

  compositorHookNames = [
    "setup"
    "ensure"
    "appEnv"
    "waitReady"
    "tick"
    "release"
    "probe"
    "recycle"
  ];

  compositorHelpers = lib.concatStringsSep "\n" (lib.mapAttrsToList (_: c: c.helpers) compositors);

  compositorFunctions = lib.concatStrings (
    lib.mapAttrsToList (
      name: c:
      lib.concatMapStrings (
        hook:
        lib.optionalString (c.hooks.${hook} != "") ''
          compositor_${name}_${hook}() {
          ${c.hooks.${hook}}
          }
        ''
      ) compositorHookNames
    ) compositors
  );

  appHelpers = lib.concatStringsSep "\n" (
    lib.unique (lib.filter (s: s != "") (map (app: app.helpers) apps))
  );

  # Shared by the session helper:
  shellCommon = ''
    rt="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    self="$(readlink -f "$0")"
    session_idle_timeout=${toString sessionIdleTimeout}
    # shellcheck disable=SC2034 # read by compositor hooks
    default_compositor=${lib.escapeShellArg defaultCompositor}
    compositor_env=()
    app_compositor=""
    sink_name="${sinkName}"
    # shellcheck disable=SC2034 # only the session helper reads this
    isolate_virt=${if isolateVirtualControllers then "1" else "0"}
    # inputInjection: backend consumes virtual devices
    # shellcheck disable=SC2034 # only the session helper reads this
    input_inject=${if lib.any (c: c.inputBridge) (lib.attrValues compositors) then "1" else "0"}

    ${compositorHelpers}
    ${compositorFunctions}
    ${appHelpers}
    ${hookFunctions}
    # App hook dispatch: the app's own app_<slug>_<hook> when defined, else the generic default.
    app_call() {
      local fn="app_''${app_slug}_$1"
      if declare -F "$fn" >/dev/null 2>&1; then
        "$fn"
      else
        "default_app_$1"
      fi
    }

    compositor_call() {
      local hook="$1" fn
      shift
      fn="compositor_''${app_compositor}_$hook"
      if declare -F "$fn" >/dev/null 2>&1; then
        "$fn" "$@"
      fi
    }

    # Generic liveness: the launcher's process group (pid == pgid under setsid).
    default_app_alive() {
      local pg
      pg="$(cat "$app_pgid_file" 2>/dev/null || true)"
      case "$pg" in "" | *[!0-9]*) return 1 ;; esac
      kill -0 -- "-$pg" 2>/dev/null
    }

    # Session pids for audio attribution (pgrep exits 1 on no match).
    default_app_pids() {
      local pg
      pg="$(cat "$app_pgid_file" 2>/dev/null || true)"
      case "$pg" in "" | *[!0-9]*) return 0 ;; esac
      pgrep -g "$pg" 2>/dev/null || true
    }

    default_app_tick() { compositor_call tick; }

    # Generic teardown: the app's scope when it runs in one, then its process group.
    default_app_stop() {
      local pg
      if [ "$scope_used" = 1 ]; then
        systemctl stop --quiet "$app_scope" 2>/dev/null || true
        systemctl reset-failed "$app_scope" 2>/dev/null || true
      fi
      pg="$(cat "$app_pgid_file" 2>/dev/null || true)"
      case "$pg" in "" | *[!0-9]*) return 0 ;; esac
      kill -TERM -- "-$pg" 2>/dev/null || true
      for _ in $(seq 1 50); do
        kill -0 -- "-$pg" 2>/dev/null || break
        sleep 0.1
      done
      kill -KILL -- "-$pg" 2>/dev/null || true
      rm -f "$app_pgid_file"
    }

    # A compositor crash must not leave an app on a dead display.
    default_app_drain() { app_call stop; }

    default_app_start() {
      if [ "''${#app_cmd[@]}" -eq 0 ]; then
        echo "sunshine-headless: app '$app_name' has no command to launch" >&2
        return 1
      fi
      launch_app
    }

    # Resolve an app name into the variables the generic code and the hooks use.
    app_setup() {
      app_name=""
      app_slug=""
      app_compositor=""
      app_home=""
      app_shim=0
      app_cmd=()
      app_env=()
      app_unset_env=()
      # Per-session app id gamescope learns from the app's windows (see app_present).
      app_appid=""
      case "''${1:-}" in
    ${appCases}    *)
          echo "sunshine-headless: unknown app ''${1:-}" >&2
          return 1
          ;;
      esac
      # Per-app session overrides; every case arm sets them (see appCases).
      app_isolate_phys=$app_s_exclude_host
      app_pause=$app_s_pause
      # shellcheck disable=SC2034 # read by the recycle verb only
      app_idle_timeout=$app_s_idle
      # A system scope is needed only when this app is device-isolated or pausable, and the
      # module installs the matching polkit rule only then. Touching the system manager
      # otherwise makes an unprivileged `systemctl` ask for a password.
      scope_used=$(( app_isolate_phys || app_pause ))
      app_scope="sunshine-headless-$app_slug.scope"
      app_pgid_file="$rt/sunshine-headless-app-$app_slug.pgid"
      app_log="$rt/sunshine-headless-app-$app_slug.log"
      # shellcheck disable=SC2034 # read by the session helper's start/stop verbs only
      app_active_file="$rt/sunshine-headless-app-$app_slug.active"
      # /etc/profiles is invisible in a Steam FHS bwrap (/etc is tmpfs); /run and /home are bound.
      # Append, so the session's own store dirs still win for its binaries.
      app_path="$PATH:/run/wrappers/bin:''${app_home:-$HOME}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
      compositor_call setup
      return 0
    }

    # Launch the app: optional scope (device policy, pause), then
    # setpriv (the caller is Sunshine, which holds cap_sys_admin) and the optional gid shim.
    launch_app() {
      # A leftover file from a crash or a hook-owned stop would satisfy the wait below.
      rm -f "$app_pgid_file"
      local -a env_args=(
        "PATH=$app_path"
        "PULSE_SINK=$sink_name"
        # proton-launch redirects its own stdout/stderr there, so one file per app.
        "PROTON_LAUNCH_LOG=$rt/sunshine-headless-app-$app_slug.proton.log"
        "SUNSHINE_HEADLESS_PGID=$app_pgid_file"
      )
      if [ -n "$app_home" ]; then
        # A fresh account dir: apps (Steam) fail outright when it is missing.
        mkdir -p "$app_home" || true
        env_args+=("HOME=$app_home")
      fi
      # Sunshine runs this helper from its store bin dir, and apps would inherit that.
      cd "''${app_home:-$HOME}" || true
      compositor_env=()
      compositor_call appEnv
      env_args+=("''${compositor_env[@]}")
      env_args+=("''${app_env[@]}")
      local n e keep
      local -a unset_args=()
      for n in "''${app_unset_env[@]}"; do
        unset_args+=("-u" "$n")
      done
      # POSIX env stops parsing options at the first assignment, so -u must lead AND the
      # module's own defaults for an unset var must vanish (else the assignment re-adds it).
      local -a launch_env=()
      for e in "''${env_args[@]}"; do
        keep=1
        for n in "''${app_unset_env[@]}"; do
          case "$e" in "$n="*) keep=0 ;; esac
        done
        [ "$keep" = 1 ] && launch_env+=("$e")
      done
      local -a wrap=()
      if [ "$app_shim" = 1 ]; then
        wrap=(/run/wrappers/bin/sunshine-headless-gid)
      fi
      if [ "$scope_used" = 1 ]; then
        # excludeHostControllers: root-managed scope denying /dev/input+hidraw.
        # pauseOnDisconnect: same scope (plain policy) so the tree freezes/thaws as one cgroup.
        # No --uid/--gid here: the payload keeps the caller's credentials either way, and the
        # daemon's `input` group is what the uaccess-stripped forwarded nodes need.
        systemctl thaw "$app_scope" 2>/dev/null || true
        systemctl stop --quiet "$app_scope" 2>/dev/null || true
        systemctl reset-failed "$app_scope" 2>/dev/null || true
        local -a device_args=()
        if [ "$app_isolate_phys" = 1 ]; then
          device_args=(-p DevicePolicy=closed ${deviceAllowRunArgs})
        fi
        setsid systemd-run --scope --quiet --collect \
          --unit="$app_scope" \
          "''${device_args[@]}" \
          -- env "''${unset_args[@]}" "''${launch_env[@]}" \
            setpriv --inh-caps=-all --ambient-caps=-all -- \
            ${pgShell} "${pgRecord}" \
            "''${wrap[@]}" "''${app_cmd[@]}" \
          >"$app_log" 2>&1 &
      else
        env "''${unset_args[@]}" "''${launch_env[@]}" \
          setpriv --inh-caps=-all --ambient-caps=-all -- \
          setsid -f ${pgShell} "${pgRecord}" \
          "''${wrap[@]}" "''${app_cmd[@]}" >"$app_log" 2>&1
      fi
      # The app records its pgid as its first instruction; give it a moment so an immediate
      # `wait` never mistakes a missing file for an app that already exited.
      for _ in $(seq 1 50); do
        [ -s "$app_pgid_file" ] && return 0
        sleep 0.1
      done
      echo "sunshine-headless: app '$app_name' did not start within 5s (see: $app_log)" >&2
      return 1
    }

    # Sunshine's devices carry its name prefixes; a host pad is virtual too when it is
    # Bluetooth (uhid), so the prefix is what tells them apart. hidraw uses HID_NAME.
    is_session_input() {
      local nm
      nm="$(cat "$1/device/name" 2>/dev/null || sed -n 's/^HID_NAME=//p' "$1/device/uevent" 2>/dev/null | head -n1)"
      case "$nm" in
        Sunshine\ * | libvirtualhid\ *) return 0 ;;
      esac
      return 1
    }

    # Recompute a scope's DeviceAllow: DevicePolicy=closed plus every virtual input node,
    # pushing only on change. A shimmed app makes its own pads (Steam Input) under names it
    # chooses, so it keeps the broad virtual match; a plain app gets the session's own
    # devices only, or a Bluetooth host pad would be allowed in with them.
    refresh_scope_allow() {
      local scope="$1" shim="$2" dd allow=() cur
      for dd in /sys/class/input/event* /sys/class/input/js* /sys/class/hidraw/hidraw*; do
        [ -e "$dd" ] || continue
        case "$(readlink -f "$dd/device" 2>/dev/null)" in
          /sys/devices/virtual/*) ;;
          *) continue ;;
        esac
        [ "$shim" = 1 ] || is_session_input "$dd" || continue
        case "$dd" in
          */hidraw*) allow+=("DeviceAllow=/dev/$(basename "$dd") rwm") ;;
          *) allow+=("DeviceAllow=/dev/input/$(basename "$dd") rwm") ;;
        esac
      done
      cur="''${allow[*]}"
      # Nothing allowed and nothing to withdraw: keep the state a previous push left.
      [ "$cur" = "''${last_allow:-}" ] && return 0
      # Never silence this: a denied set-property means the pads stay blocked and the
      # app sees no controller at all. Log the transition, keep retrying.
      if systemctl set-property --runtime "$scope" \
          DevicePolicy=closed ${deviceAllowSetArgs} "''${allow[@]}" >/dev/null 2>&1; then
        last_allow="$cur"
        allow_failed=0
        return 0
      fi
      if [ "''${allow_failed:-0}" != 1 ]; then
        echo "sunshine-headless: DeviceAllow refresh on $scope failed; Moonlight controllers will not reach the app" >&2
        allow_failed=1
      fi
      return 0
    }

    # With isolation on, virtual streaming devices must be uaccess-stripped so nobody
    # opens them without the shim. Warns, never blocks.
    verify_input_isolation() {
      [ "$bridge_needed" = 1 ] || return 0
      local user name node leaked=0 node_dev
      user="$(id -un)"
      for node in /sys/class/input/event*; do
        [ -e "$node/device/name" ] || continue
        name="$(cat "$node/device/name" 2>/dev/null || true)"
        case "$name" in
          Sunshine\ * | libvirtualhid\ *) ;;
          *) continue ;;
        esac
        # uaccess-strip applies only to the class whose udev rule is installed.
        case "$name" in
          libvirtualhid\ *) [ "$input_inject" = 1 ] || continue ;;
          *) [ "$isolate_virt" = 1 ] || continue ;;
        esac
        node_dev="/dev/input/''${node##*/}"
        if getfacl -p -c "$node_dev" 2>/dev/null | grep -q "^user:''${user}:"; then
          echo "sunshine-headless: uaccess NOT stripped on $node_dev ('$name'); the streaming user can open it without the shim" >&2
          leaked=1
        fi
      done
      return "$leaked"
    }

    audio_pid_in_session() {
      local p="$1"
      for _ in $(seq 1 32); do
        case "$p" in "" | 0 | 1) return 1 ;; esac
        case "$2" in *" $p "*) return 0 ;; esac
        p="$(awk '{sub(/^.*\) /, ""); print $2}' "/proc/$p/stat" 2>/dev/null || true)"
      done
      return 1
    }

    # Pin this app's audio to the capture sink (default-following apps escape PULSE_SINK).
    route_session_audio() {
      local target sess ci pid idx sinkid
      target="$(pactl list short sinks 2>/dev/null | awk -v s="$sink_name" '$2==s {print $1; exit}')"
      [ -n "$target" ] || return 0
      sess=" $(app_call pids | tr '\n' ' ')"
      # Resolve sink-inputs via their pulse-client (some apps omit application.process.id).
      declare -A cpid
      while IFS=$'\t' read -r ci pid; do cpid[$ci]="$pid"; done < <(
        LC_ALL=C pactl list clients 2>/dev/null | awk '
          function flush() { if (c != "") { p = (appid != "" ? appid : secpid); if (p != "") print c "\t" p } }
          /^Client #/ { flush(); c=substr($2,2); appid=""; secpid=""; next }
          /application\.process\.id = / { v=$3; gsub(/"/,"",v); appid=v }
          /pipewire\.sec\.pid = / { v=$3; gsub(/"/,"",v); secpid=v }
          END { flush() }')
      while IFS=$'\t' read -r idx sinkid ci; do
        [ "$sinkid" = "$target" ] && continue
        pid="''${cpid[$ci]:-}"
        [ -n "$pid" ] || continue
        audio_pid_in_session "$pid" "$sess" || continue
        pactl move-sink-input "$idx" "$sink_name" 2>/dev/null || true
      done < <(LC_ALL=C pactl list sink-inputs 2>/dev/null | awk '
        /^Sink Input #/ { idx=substr($3,2); sink=""; cli=""; next }
        /^[[:space:]]*Client:[[:space:]]/ { cli=$2; next }
        /^[[:space:]]*Sink:[[:space:]]/ { sink=$2; if (idx!="") print idx"\t"sink"\t"cli }')
    }
  '';

  sessionApp = writeShellApplication {
    name = "sunshine-headless";

    runtimeInputs =
      (lib.concatMap (c: c.packages) (lib.attrValues compositors))
      ++ lib.concatMap (app: app.packages) apps
      ++ (with pkgs; [
        coreutils
        gawk # awk: parse pactl output in the per-stream audio mover
        acl # getfacl: verify headless pads are uaccess-stripped
        procps
        pulseaudio # pactl: create/destroy the on-demand null-sink, move app streams onto it
        systemd # systemd-run/systemctl: cgroup device-policy scope for the app tree
        util-linux
        wireplumber
      ]);

    text = ''
      ${shellCommon}

      # The helper needs the REAL user session bus (not the private portal bus).
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus"
      # Unset the daemon's XDG_CONFIG_HOME redirect: apps use $HOME/.config, not the isolated state dir.
      unset XDG_CONFIG_HOME

      # Only these install a 72-sunshine-headless-*-no-uaccess.rules udev rule, so only
      # they have uaccess stripping worth verifying; a shim-only app adds none.
      bridge_needed=0
      case "''${isolate_virt}''${input_inject}" in
        *1*) bridge_needed=1 ;;
      esac

      # Sunshine opens a new connection per capture, so the swap takes effect before capture.
      retarget_portal() {
        mkdir -p "$rt/sunshine-portal"
        ln -sfn "$rt/sunshine-portal/$1/bus" "$rt/sunshine-portal/bus.new"
        mv -T "$rt/sunshine-portal/bus.new" "$rt/sunshine-portal/bus"
      }

      retarget_portal_away_from() {
        if [ "$(readlink "$rt/sunshine-portal/bus" 2>/dev/null || true)" = "$rt/sunshine-portal/$1/bus" ]; then
          retarget_portal "$default_compositor"
        fi
      }

      streaming_active() {
        local address="unix:path=$rt/sunshine-portal/$1/bus"
        # tree would bus-activate a portal without the unit's env, and it keeps the name.
        busctl --address="$address" call org.freedesktop.DBus / org.freedesktop.DBus \
          NameHasOwner s org.freedesktop.portal.Desktop 2>/dev/null | grep -q true || return 1
        busctl --address="$address" tree org.freedesktop.portal.Desktop 2>/dev/null \
          | grep -q '/session/'
      }

      recycle_stop_sessions() {
        local target="$1" f name
        for f in "$rt"/sunshine-headless-app-*.active; do
          [ -e "$f" ] || continue
          name="$(cat "$f" 2>/dev/null || true)"
          [ -n "$name" ] || continue
          ( app_setup "$name" >/dev/null 2>&1 && [ "$app_compositor" = "$target" ] ) || continue
          "$0" stop "$name" || true
        done
      }

      case "''${1:-}" in
        start)
          app_setup "''${2:-}" || exit 1
          start_ok=0
          trap '[ "$start_ok" = 1 ] || "$0" stop "$app_name" || true' EXIT
          # Heartbeat for the recycle timer: age of this file = minutes since the last stream.
          touch "$rt/sunshine-headless-stream-hb-$app_compositor" 2>/dev/null || true
          # Record the pre-stream desktop default sink (restored once the last app stops).
          for _ in $(seq 1 10); do
            did="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP '^id \K[0-9]+' || true)"
            dname="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'node.name = "\K[^"]+' || true)"
            case "$dname" in
              "" | "$sink_name" | sink-sunshine-*) : ;;
              *)
                printf '%s' "$did" >"$rt/sunshine-headless-default-sink"
                break
                ;;
            esac
            sleep 0.2
          done

          # On-demand null-sink as system default (apps follow it); `stop` unloads it.
          if ! pactl list short sinks 2>/dev/null | grep -qw "$sink_name"; then
            pactl load-module module-null-sink \
              media.class=Audio/Sink \
              sink_name="$sink_name" \
              channel_map=front-left,front-right \
              sink_properties=${lib.escapeShellArg sinkProperties} \
              >"$rt/sunshine-headless-sink-module" 2>/dev/null || true
          fi
          pactl set-default-sink "$sink_name" 2>/dev/null || true

          retarget_portal "$app_compositor"

          compositor_call ensure \
            "''${SUNSHINE_CLIENT_WIDTH:-}" \
            "''${SUNSHINE_CLIENT_HEIGHT:-}" \
            "''${SUNSHINE_CLIENT_FPS:-}" \
            "''${SUNSHINE_CLIENT_HDR:-}"
          # The app's own start hook does the app-specific work (window wait, pre-kill, ...).
          app_call start || exit 1
          # Past this point the app owns the session, so the EXIT trap must not stop it.
          start_ok=1
          printf '%s' "$app_name" >"$app_active_file"
          ;;
        wait)
          app_setup "''${2:-}" || exit 1
          # Ticks tag windows on these; empty values only make them no-ops.
          compositor_call waitReady
          # Keep the desktop default off the stream/sunshine sinks (Sunshine re-defaults its own).
          last_default="$(cat "$rt/sunshine-headless-default-sink" 2>/dev/null || true)"
          iso_tick=0
          iso_warned=0

          # Block while the app lives (apps that re-exec report liveness themselves).
          for _ in $(seq 1 60); do
            app_call alive && break
            sleep 0.5
          done
          # ...then block until it's been gone 3s straight (rides the re-exec gap).
          gone=0
          frozen=0
          idle_since=""
          while :; do
            if app_call alive; then
              gone=0
              # Throttled input-isolation check; warn once when a virtual device escaped.
              iso_tick=$(( iso_tick + 1 ))
              if [ $(( iso_tick % 15 )) -eq 1 ] && [ "''${iso_warned:-0}" != 1 ] && ! verify_input_isolation; then
                iso_warned=1
              fi
              # pauseOnDisconnect: freeze the app tree ~10s after the last client
              # leaves, thaw on reconnect (gamescope keeps running).
              if [ "$app_pause" = 1 ]; then
                if streaming_active "$app_compositor"; then
                  idle_since=""
                  if [ "$frozen" = 1 ]; then
                    systemctl thaw "$app_scope" 2>/dev/null || true
                    frozen=0
                  fi
                else
                  [ -n "$idle_since" ] || idle_since="$(date +%s)"
                  if [ "$frozen" != 1 ] && [ "$(( $(date +%s) - idle_since ))" -ge 10 ] \
                      && systemctl is-active --quiet "$app_scope" 2>/dev/null; then
                    systemctl freeze "$app_scope" 2>/dev/null && frozen=1
                  fi
                fi
              fi
              route_session_audio
              # Recompute the scope's DeviceAllow each tick, pushing only on change. udev
              # runs the same function (verb `refresh`) when a session device appears, so a
              # pad the client announces mid-run is allowed before the app hears about it.
              if [ "$app_isolate_phys" = 1 ]; then
                refresh_scope_allow "$app_scope" "$app_shim"
              fi
              app_call tick || true
              dname="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'node.name = "\K[^"]+' || true)"
              case "$dname" in
                "$sink_name" | sink-sunshine-*)
                  [ -n "$last_default" ] && wpctl set-default "$last_default" 2>/dev/null || true
                  ;;
                "")
                  : ;;
                *)
                  # Persist user real-device choice so stop restores last known default.
                  did="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP '^id \K[0-9]+' || true)"
                  if [ -n "$did" ] && [ "$did" != "$last_default" ]; then
                    last_default="$did"
                    printf '%s' "$last_default" >"$rt/sunshine-headless-default-sink"
                  fi
                  ;;
              esac
            else
              gone=$(( gone + 1 ))
              [ "$gone" -ge 6 ] && break
            fi
            sleep 0.5
          done
          "$0" stop "$app_name" || true
          ;;
        stop)
          app_setup "''${2:-}" || exit 1
          # A paused app is frozen and would ignore TERM.
          if [ "$scope_used" = 1 ] && systemctl is-active --quiet "$app_scope" 2>/dev/null; then
            systemctl thaw "$app_scope" 2>/dev/null || true
          fi
          app_call stop || true
          # Hooks need not know the file, so the verb clears it (see launch_app).
          rm -f "$app_pgid_file" "$app_active_file"

          stopped_compositor="$app_compositor"
          compositor_busy=0
          for f in "$rt"/sunshine-headless-app-*.active; do
            [ -e "$f" ] || continue
            other="$(cat "$f" 2>/dev/null || true)"
            if ( app_setup "$other" >/dev/null 2>&1 && [ "$app_compositor" = "$stopped_compositor" ] && app_call alive ); then
              compositor_busy=1
            fi
          done
          [ "$compositor_busy" = 1 ] || compositor_call release || true

          # The sink is session-wide: only the last app out restores the desktop default.
          # A rebuild can rename or drop an app that still has an .active file, and a
          # hook-owned stop can leave one behind, so prune what no longer resolves or lives.
          for f in "$rt"/sunshine-headless-app-*.active; do
            [ -e "$f" ] || continue
            other="$(cat "$f" 2>/dev/null || true)"
            # Subshell: app_setup overwrites the globals of the app just stopped.
            if [ -z "$other" ] || ! ( app_setup "$other" >/dev/null 2>&1 && app_call alive ); then
              rm -f "$f"
              continue
            fi
            exit 0
          done
          real="$(cat "$rt/sunshine-headless-default-sink" 2>/dev/null || true)"
          [ -n "$real" ] && wpctl set-default "$real" 2>/dev/null || true
          mod="$(cat "$rt/sunshine-headless-sink-module" 2>/dev/null || true)"
          [ -n "$mod" ] && pactl unload-module "$mod" 2>/dev/null || true
          rm -f "$rt/sunshine-headless-sink-module"
          ;;
        cleanup)
          # SIGKILLed Sunshine skips `stop`: release just the audio half (never the apps).
          dname="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'node.name = "\K[^"]+' || true)"
          case "$dname" in
            "$sink_name" | sink-sunshine-*)
              real="$(cat "$rt/sunshine-headless-default-sink" 2>/dev/null || true)"
              [ -n "$real" ] && wpctl set-default "$real" 2>/dev/null || true
              ;;
          esac
          mod="$(cat "$rt/sunshine-headless-sink-module" 2>/dev/null || true)"
          [ -n "$mod" ] && pactl unload-module "$mod" 2>/dev/null || true
          rm -f "$rt/sunshine-headless-sink-module"
          ;;
        drain)
          # Unit ExecStopPost passes its compositor; an intentional stop leaves a marker.
          drain_target="''${2:-}"
          if [ -n "$drain_target" ] && [ -e "$rt/sunshine-headless-$drain_target-stopping" ]; then
            rm -f "$rt/sunshine-headless-$drain_target-stopping"
            exit 0
          fi
          for f in "$rt"/sunshine-headless-app-*.active; do
            [ -e "$f" ] || continue
            name="$(cat "$f" 2>/dev/null || true)"
            [ -n "$name" ] || continue
            app_setup "$name" || continue
            [ -z "$drain_target" ] || [ "$app_compositor" = "$drain_target" ] || continue
            # A paused app is frozen and would ignore TERM.
            if [ "$scope_used" = 1 ] && systemctl is-active --quiet "$app_scope" 2>/dev/null; then
              systemctl thaw "$app_scope" 2>/dev/null || true
            fi
            app_call drain || true
          done
          ;;
        idle)
          app_compositor="$default_compositor"
          compositor_call probe
          ;;
        recycle)
          ${lib.optionalString (compositors != { }) ''
            # shellcheck disable=SC2043 # backend list can contain only one item
            for c in ${lib.escapeShellArgs (lib.attrNames compositors)}; do
              if declare -F "compositor_''${c}_recycle" >/dev/null 2>&1; then
                "compositor_''${c}_recycle"
              fi
            done
          ''}
          ;;
        refresh)
          # udev RUN target (72-sunshine-headless-scope-refresh.rules): a device the session
          # creates mid-run must be in the app scope's allow list before udev hands that event
          # to libudev, because that is when the app opens the device. A RUN program cannot
          # count on the caller's runtime dir, so the live app scopes come from sysfs instead,
          # and app_setup takes a scope name as well as an app name. Best effort: always exits
          # 0, so a failure here can never block the udev event.
          # A RUN program gets no HOME either, and app_setup reads it.
          export HOME="''${HOME:-/}"
          for d in /sys/fs/cgroup/system.slice/sunshine-headless-*.scope; do
            [ -e "$d" ] || continue
            app_setup "$(basename "$d")" >/dev/null 2>&1 || continue
            [ "$app_isolate_phys" = 1 ] || continue
            refresh_scope_allow "$app_scope" "$app_shim"
          done
          exit 0
          ;;
        retarget-default)
          retarget_portal "$default_compositor"
          ;;
        *)
          echo "usage: sunshine-headless start <app>|wait <app>|stop <app>|drain [compositor]|cleanup|idle|recycle|refresh|retarget-default" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  inherit sessionApp;
}
