# Runtime shell: the idle gamescope and the generic per-app session helper.
# Apps come from icedos.applications.sunshine-headless.apps and supply shell hooks;
# scripts.nix dispatches app_<slug>_<hook> and falls back to default_app_<hook>.
{
  pkgs,
  lib,
  cfg,
  headlessSeat,
  gamescopePkg,
  xnudge,
  # cfg.apps resolved by icedos.nix: slug, launcher and hooks merged per entry.
  apps,
}:

let
  inherit (pkgs) writeShellApplication;

  inherit (cfg) gamescope session;

  fsrSharpness = gamescope.fsrSharpness;
  hdr = gamescope.hdr;
  inputInjection = gamescope.inputInjection;
  isolateVirtualControllers = session.controllers.isolateVirtual;
  mangoApp = gamescope.mangoApp;
  nativeWayland = gamescope.nativeWayland;
  realtime = gamescope.realtime;
  renderHeight = gamescope.renderHeight;
  renderWidth = gamescope.renderWidth;
  sdrContentNits = gamescope.sdrContentNits;
  sdrGamutWideness = gamescope.sdrGamutWideness;
  sessionIdleTimeout = session.idleTimeout;
  gamescopeRegrowTimeout = gamescope.regrowTimeout;
  upscaleFilter = gamescope.upscaleFilter;

  sinkName = "sunshine-headless-sink";
  # One pulse property string; built here so a quote in the name cannot break the shell word.
  sinkProperties = "node.description=\"${session.sunshine.name} (headless)\"";
  gamescopeUnit = "sunshine-headless-gamescope.service";
  # Intentional stops (stop_gamescope/start_gamescope) create this marker; the drain skips them.
  stoppingMarker = "sunshine-headless-gamescope-stopping";

  # Gamescope flags (HDR, upscale/FSR, render size, --rt, mangoapp, input shim) are per app:
  # the shell builds them from the app's effective settings, and the module-global options
  # above are the fallbacks for the app-less paths (idle, recycle).

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

  # Shadow `mangoapp` with an X11-forcing wrapper (native-Wayland GLFW coredumps, MangoHud #1741).
  mangoappWrapper = pkgs.writeShellScriptBin "mangoapp" ''
    unset WAYLAND_DISPLAY
    export XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 DISPLAY=:1
    exec ${pkgs.mangohud}/bin/mangoapp "$@"
  '';

  # The helper records the new session's pgid and execs `command`, so an app needs no
  # launcher wrapper (see pgRecord).
  appCmdLine = app: "app_cmd=(${lib.concatMapStringsSep " " lib.escapeShellArg app.command})";

  # Per-app gamescope settings as one associative array: `app_g[hdr]`, `app_g[render_w]`, ...
  # `app_setup` re-assigns the whole array per app, so no stale key survives.
  appGamescopeLine =
    app:
    let
      inherit (app.gamescope)
        fsrSharpness
        hdr
        inputInjection
        mangoApp
        nativeWayland
        realtime
        renderHeight
        renderWidth
        sdrContentNits
        sdrGamutWideness
        upscaleFilter
        ;
    in
    "      app_g=(${
            lib.concatStringsSep " " [
              "[hdr]=${if hdr then "1" else "0"}"
              "[nits]=${toString sdrContentNits}"
              "[gamut]=${toString sdrGamutWideness}"
              "[render_w]=${toString renderWidth}"
              "[render_h]=${toString renderHeight}"
              "[upscale]=${lib.escapeShellArg upscaleFilter}"
              "[fsr]=${toString fsrSharpness}"
              "[native_wayland]=${if nativeWayland then "1" else "0"}"
              "[input_inject]=${if inputInjection then "1" else "0"}"
              "[mango]=${if mangoApp then "1" else "0"}"
              "[realtime]=${if realtime then "1" else "0"}"
            ]
          })";

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

  appHelpers = lib.concatStringsSep "\n" (
    lib.unique (lib.filter (s: s != "") (map (app: app.helpers) apps))
  );

  # One case arm per app: name is the lookup key, slug drives every runtime path.
  appCases = lib.concatMapStrings (app: ''
    ${lib.escapeShellArg app.name} | ${lib.escapeShellArg "sunshine-headless-${app.slug}.scope"})
      app_name=${lib.escapeShellArg app.name}
      app_slug=${lib.escapeShellArg app.slug}
      app_home=${lib.escapeShellArg app.home}
      app_shim=${if app.shim then "1" else "0"}
      app_steam_mode=${if app.steamMode then "1" else "0"}
      app_s_idle=${toString app.session.idleTimeout}
      app_s_pause=${if app.session.pauseOnDisconnect then "1" else "0"}
      app_s_exclude_host=${if app.session.controllers.excludeHost then "1" else "0"}
      ${appGamescopeLine app}
      ${appCmdLine app}
      ${appEnvLine app}
      ;;
  '') apps;

  # Shared by the session helper and the gamescope drain: has to live in both.
  shellCommon = ''
    rt="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    # Per-app gamescope settings (see appCases); `declare` at file scope keeps it global.
    declare -A app_g=()
    sink_name="${sinkName}"
    # shellcheck disable=SC2034 # only the session helper reads this; the drain sources it too
    isolate_virt=${if isolateVirtualControllers then "1" else "0"}
    # inputInjection: patched gamescope matches the seat-suffixed passthrough names (fail-closed).
    # shellcheck disable=SC2034 # only the session helper reads this; the drain sources it too
    input_inject=${if inputInjection then "1" else "0"}

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

    # gamescope (--steam) presents a window only when the app that owns it is the
    # focused app, and an Xwayland window carries its app id in STEAM_GAME, which nothing
    # sets for an app the module launches itself. Tag the app's windows, aim the baselayer
    # at the same id, and re-roll the focus until gamescope lists it. Ids come from the
    # app's SteamAppId, else the window pid (nonzero and unique, which is all gamescope needs).
    # Only reachable through app_call's dynamic dispatch.
    # shellcheck disable=SC2329
    app_present() {
      local w wpid a
      while read -r w; do
        [ -n "$w" ] || continue
        wpid="$(DISPLAY=:1 xprop -id "$w" _NET_WM_PID 2>/dev/null | grep -oE '[0-9]+$' || true)"
        [ -n "$wpid" ] || continue
        a="''${app_appid:-}"
        if [ -z "$a" ]; then
          a="$(tr '\0' '\n' <"/proc/$wpid/environ" 2>/dev/null | sed -n 's/^SteamAppId=//p' | head -n1 || true)"
        fi
        case "$a" in "" | 0 | *[!0-9]*) a="$wpid" ;; esac
        if ! DISPLAY=:1 xprop -id "$w" STEAM_GAME 2>/dev/null | grep -q "= $a$"; then
          DISPLAY=:1 xprop -id "$w" -f STEAM_GAME 32c -set STEAM_GAME "$a" 2>/dev/null || true
        fi
        app_appid="$a"
      done < <(DISPLAY=:1 xwininfo -root -children 2>/dev/null | grep -oE '0x[0-9a-f]+')
      [ -n "''${app_appid:-}" ] || return 0
      if [ "''${last_baselayer:-}" != "$app_appid" ]; then
        DISPLAY=:1 xprop -root -f GAMESCOPECTRL_BASELAYER_APPID 32c \
          -set GAMESCOPECTRL_BASELAYER_APPID "$app_appid" 2>/dev/null || true
        last_baselayer="$app_appid"
      fi
      if game_in_focusable "$app_appid"; then
        focus_tick=0
      else
        focus_tick=$(( ''${focus_tick:-0} + 1 ))
        if [ $(( focus_tick % 5 )) -eq 1 ]; then
          reroll_gamescope_focus
        fi
      fi
    }

    # Only reachable through app_call's dynamic dispatch.
    # shellcheck disable=SC2329
    game_in_focusable() {
      local apps
      apps="$(DISPLAY=:1 xprop -root GAMESCOPE_FOCUSABLE_APPS 2>/dev/null | sed -n 's/^.*= //p' | tr -d ' ' || true)"
      case ",$apps," in *",$1,"*) return 0 ;; esac
      return 1
    }

    # Dirtying the focus re-rolls it; every 5th tick, since a window gamescope rightly
    # rejects never reaches its list.
    # Only reachable through app_call's dynamic dispatch.
    # shellcheck disable=SC2329
    reroll_gamescope_focus() {
      DISPLAY=:2 sunshine-headless-xnudge 2>/dev/null || true
    }

    default_app_tick() {
      # Only gamescope --steam gates presentation on app ids; a plain compositor
      # focuses the app's window on its own.
      [ "''${app_steam_mode:-0}" = 1 ] && app_present
    }

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

    # A gamescope crash must not leave an app on a dead display.
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
      # Hooks match the app's processes by $HOME, so a coexisting desktop session is never touched.
      sess_home="''${app_home:-$HOME}"
      # /etc/profiles is invisible in a Steam FHS bwrap (/etc is tmpfs); /run and /home are bound.
      # Append, so the session's own store dirs still win for its binaries.
      app_path="$PATH:/run/wrappers/bin:''${app_home:-$HOME}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
      return 0
    }

    # Launch the app into the idle gamescope: optional scope (device policy, pause), then
    # setpriv (the caller is Sunshine, which holds cap_sys_admin) and the optional gid shim.
    launch_app() {
      local i
      # A leftover file from a crash or a hook-owned stop would satisfy the wait below.
      rm -f "$app_pgid_file"
      local -a env_args=(
        "DISPLAY=:1"
        "WAYLAND_DISPLAY=gamescope-0"
        "GAMESCOPE_WAYLAND_DISPLAY=gamescope-0"
        "ENABLE_GAMESCOPE_WSI=1"
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
      if [ "''${app_g[native_wayland]:-${if nativeWayland then "1" else "0"}}" != 1 ]; then
        env_args+=("QT_QPA_PLATFORM=xcb")
      fi
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
      for i in $(seq 1 50); do
        [ -s "$app_pgid_file" ] && return 0
        sleep 0.1
      done
      echo "sunshine-headless: app '$app_name' did not start within 5s (see: $app_log)" >&2
      return 1
    }
  '';

  # Teardown after an unintentional gamescope exit: one drain per active app.
  drainText = ''
    for f in "$rt"/sunshine-headless-app-*.active; do
      [ -e "$f" ] || continue
      name="$(cat "$f" 2>/dev/null || true)"
      [ -n "$name" ] || continue
      app_setup "$name" || continue
      # A paused app is frozen and would ignore TERM.
      if [ "$scope_used" = 1 ] && systemctl is-active --quiet "$app_scope" 2>/dev/null; then
        systemctl thaw "$app_scope" 2>/dev/null || true
      fi
      app_call drain || true
    done
  '';

  # ExecStopPost of the gamescope unit: a crash must not leave an app on a dead display.
  # Runs outside the KillSignal=SIGKILL sweep, which would kill an in-unit drainer first.
  drainApp = writeShellApplication {
    name = "sunshine-headless-drain";
    runtimeInputs = [
      xnudge
    ]
    ++ lib.concatMap (app: app.packages) apps
    ++ (with pkgs; [
      coreutils
      procps
      systemd
      util-linux
    ]);
    text = ''
      ${shellCommon}

      if [ -e "$rt/${stoppingMarker}" ]; then
        rm -f "$rt/${stoppingMarker}"
        exit 0
      fi
      ${drainText}
    '';
  };

  sessionApp = writeShellApplication {
    name = "sunshine-headless";

    runtimeInputs = [
      gamescopePkg
      xnudge
    ]
    ++ lib.optional mangoApp mangoappWrapper
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
      xprop # tag game windows the app left untagged so gamescope (SteamControlled) presents them
      xwininfo # enumerate top-levels on the game Xwayland
    ]);

    text = ''
      ${shellCommon}

      # The helper needs the REAL user session bus (not the private portal bus).
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus"
      # Unset the daemon's XDG_CONFIG_HOME redirect: apps use $HOME/.config, not the isolated state dir.
      unset XDG_CONFIG_HOME
      # gamescope always runs through the cap_sys_nice wrapper (SetNice(-20); --rt adds
      # realtime). Wrapper is exec'd by the gid shim when the app's inputInjection is on.
      gamescope_wrapper=(/run/wrappers/bin/sunshine-headless-gamescope)
      # The running instance must match the incoming app's effective settings, so they all
      # join the marker; `start` compares it and restarts gamescope on a mismatch.
      gamescope_marker_now() {
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s' \
          "${gamescopePkg}" \
          "''${app_g[input_inject]:-${if inputInjection then "1" else "0"}}" \
          "''${app_g[realtime]:-${if realtime then "1" else "0"}}" \
          "''${app_steam_mode:-0}" \
          "''${app_g[hdr]:-${if hdr then "1" else "0"}}" \
          "''${app_g[nits]:-${toString sdrContentNits}}" \
          "''${app_g[gamut]:-${toString sdrGamutWideness}}" \
          "''${app_g[render_w]:-${toString renderWidth}}" \
          "''${app_g[render_h]:-${toString renderHeight}}" \
          "''${app_g[upscale]:-${upscaleFilter}}"
        # --mangoapp is steam mode only, so a plain app must not restart gamescope over it.
        if [ "''${app_steam_mode:-0}" = 1 ]; then
          printf '|%s' "''${app_g[mango]:-${if mangoApp then "1" else "0"}}"
        fi
        printf '\n'
      }

      # Only these install a 72-sunshine-headless-*-no-uaccess.rules udev rule, so only
      # they have uaccess stripping worth verifying; a shim-only app adds none.
      bridge_needed=0
      case "''${isolate_virt}''${input_inject}" in
        *1*) bridge_needed=1 ;;
      esac

      # The session's own input devices carry the seat marker (XDG_SEAT, see icedos.nix);
      # a host pad is virtual too when it is Bluetooth (uhid), so the marker is what tells
      # them apart. hidraw carries its name in HID_NAME instead of a name attribute.
      is_session_input() {
        local nm
        nm="$(cat "$1/device/name" 2>/dev/null || sed -n 's/^HID_NAME=//p' "$1/device/uevent" 2>/dev/null | head -n1)"
        case "$nm" in
          *"(${headlessSeat})"*) return 0 ;;
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

      # Virtual streaming devices must carry the seat marker and, with isolation on, be
      # uaccess-stripped so nobody opens them without the shim. Warns once, never blocks.
      verify_input_isolation() {
        [ "$bridge_needed" = 1 ] || return 0
        local user name node leaked=0 node_dev
        user="$(id -un)"
        for node in /sys/class/input/event*; do
          [ -e "$node/device/name" ] || continue
          name="$(cat "$node/device/name" 2>/dev/null || true)"
          case "$name" in
            *Sunshine* | *passthrough*) ;;
            *) continue ;;
          esac
          # Every virtual device from this daemon carries the seat marker (XDG_SEAT).
          case "$name" in
            *"(${headlessSeat})"*) ;;
            *)
              # Only meaningful where a uaccess-stripping rule is actually installed.
              if { [ "$isolate_virt" = 1 ] || [ "$input_inject" = 1 ]; } && [ "''${seat_warned:-0}" != 1 ]; then
                # Primary daemon's pads legitimately lack the marker: warn once, never latch leaked.
                echo "sunshine-headless: virtual input device '$name' lacks the headless seat marker (${headlessSeat}); it may collide with the primary daemon and evade uaccess stripping" >&2
                seat_warned=1
              fi
              continue
              ;;
          esac
          # uaccess-strip applies only to the class whose udev rule is installed.
          case "$name" in
            *passthrough*) [ "$input_inject" = 1 ] || continue ;;
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

      # Intentional stop: the marker tells the ExecStopPost drain to leave the apps alone.
      # No is-active guard: a crash-looping unit exits 3 there, skipping the stop that cancels its restart.
      stop_gamescope_unit() {
        : >"$rt/${stoppingMarker}"
        systemctl --user stop --quiet ${gamescopeUnit} 2>/dev/null || true
        # stop blocks through ExecStopPost; clear a marker no drain consumed.
        rm -f "$rt/${stoppingMarker}"
      }

      stop_gamescope() {
        # Killing a Restart=always unit (or freezing it) instead of stopping it latches it on systemd 261.
        stop_gamescope_unit
        systemctl --user reset-failed ${gamescopeUnit} 2>/dev/null || true
        for _ in $(seq 1 30); do
          [ ! -S "$rt/gamescope-0" ] && break
          sleep 0.1
        done
        rm -f "$rt/gamescope-0" "$rt/sunshine-headless-gamescope-params" "$rt/sunshine-headless-gamescope-bin"
      }

      start_gamescope() {
        local w="$1" h="$2" fps="$3" hdr_on="$4"
        local rw="''${app_g[render_w]:-${toString renderWidth}}" rh="''${app_g[render_h]:-${toString renderHeight}}"
        [ "$rw" = "0" ] && rw="$w"
        [ "$rh" = "0" ] && rh="$h"
        local hdr_args=()
        if [ "''${app_g[hdr]:-${if hdr then "1" else "0"}}" = 1 ] && [ "$hdr_on" = 1 ]; then
          hdr_args=(
            --hdr-enabled
            --hdr-debug-force-output
            --hdr-debug-force-support
            --sdr-gamut-wideness "''${app_g[gamut]:-${toString sdrGamutWideness}}"
            --hdr-sdr-content-nits "''${app_g[nits]:-${toString sdrContentNits}}"
          )
        fi
        upscale_args=()
        if [ -n "''${app_g[upscale]:-${upscaleFilter}}" ]; then
          upscale_args=(-F "''${app_g[upscale]:-${upscaleFilter}}" --fsr-sharpness "''${app_g[fsr]:-${toString fsrSharpness}}")
        fi
        rt_args=()
        [ "''${app_g[realtime]:-${if realtime then "1" else "0"}}" = 1 ] && rt_args=(--rt)
        # The gid shim is what turns the passthrough pads into this session's input devices.
        gscope_wrap=()
        input_args=()
        if [ "''${app_g[input_inject]:-${if inputInjection then "1" else "0"}}" = 1 ]; then
          gscope_wrap=(/run/wrappers/bin/sunshine-headless-gid)
          input_args=(
            --setenv=HEADLESS_INPUT_KEYBOARD="Keyboard passthrough (${headlessSeat})"
            --setenv=HEADLESS_INPUT_MOUSE="Mouse passthrough (${headlessSeat})"
            --setenv=HEADLESS_INPUT_MOUSE_ABS="Mouse passthrough (${headlessSeat}) (absolute)"
          )
        fi
        # Plain apps do not need (and are not gated by) --steam; the mangoapp overlay is
        # a full-screen X window and would fight them for focus, so it stays steam-only.
        steam_args=()
        mango_args=()
        if [ "''${app_steam_mode:-0}" = 1 ]; then
          steam_args=(--steam)
          [ "''${app_g[mango]:-${if mangoApp then "1" else "0"}}" = 1 ] && mango_args=(--mangoapp)
        fi
        printf '%s %s %s %s' "$w" "$h" "$fps" "$hdr_on" >"$rt/sunshine-headless-gamescope-params"
        # Record the gamescope store path + argv so a stale one is restarted in `start`.
        printf '%s' "$(gamescope_marker_now)" >"$rt/sunshine-headless-gamescope-bin"

        gamescope_env="DISPLAY=:1 ENABLE_GAMESCOPE_WSI=1 PATH=${lib.optionalString mangoApp "${mangoappWrapper}/bin:"}${gamescopePkg}/bin"
        # --mangoapp is steam mode only, so a plain app gets no MANGOHUD_CONFIGFILE (the file
        # is written for steam-mode apps only, see the start verb).
        if [ "''${app_steam_mode:-0}" = 1 ] && [ "''${app_g[mango]:-${if mangoApp then "1" else "0"}}" = 1 ]; then
          gamescope_env="$gamescope_env MANGOHUD_CONFIGFILE=$rt/sunshine-mangoapp.conf"
        fi

        # Free the transient unit first: a leftover makes systemd-run refuse the name.
        rm -f "$rt/gamescope-0"
        systemctl --user reset-failed ${gamescopeUnit} 2>/dev/null || true
        stop_gamescope_unit
        # KillSignal=SIGKILL skips gamescope's destructor path on stop.
        systemd-run --user \
          --collect \
          --unit=${gamescopeUnit} \
          --property=Type=simple \
          --property=Restart=always \
          --property=KillSignal=SIGKILL \
          --property=ExecStopPost=${drainApp}/bin/sunshine-headless-drain \
          --same-dir \
          --property="Environment=$gamescope_env" \
          "''${input_args[@]}" \
          -- "''${gscope_wrap[@]}" "''${gamescope_wrapper[@]}" "''${rt_args[@]}" \
              --backend headless \
              --expose-wayland \
              "''${steam_args[@]}" \
              --xwayland-count 2 \
              "''${mango_args[@]}" \
              "''${hdr_args[@]}" \
              "''${upscale_args[@]}" \
              -W "$w" -H "$h" -r "$fps" \
              -w "$rw" -h "$rh" \
              -- ${pkgs.coreutils}/bin/sleep infinity

        for _ in $(seq 1 300); do
          [ -S "$rt/gamescope-0" ] && break
          sleep 0.1
        done
        # Surface a launch failure instead of streaming a black frame.
        if [ ! -S "$rt/gamescope-0" ]; then
          echo "sunshine-headless: gamescope-0 never appeared within 30s of start_gamescope -W $w -H $h -r $fps (see: journalctl --user -u ${gamescopeUnit})" >&2
          exit 1
        fi
        sleep 1
      }

      # True while a client streams: the ScreenCast session on the PRIVATE portal bus
      # lives only while its video-capture thread runs (the helper uses the real user bus).
      streaming_active() {
        busctl --address="unix:path=$rt/sunshine-portal/bus" tree org.freedesktop.portal.Desktop 2>/dev/null \
          | grep -q '/session/'
      }

      # Recycle teardown: the full `stop` path per active app (idempotent; an app's own
      # undo may race in and re-run it, which is a no-op).
      recycle_stop_sessions() {
        local f name
        for f in "$rt"/sunshine-headless-app-*.active; do
          [ -e "$f" ] || continue
          name="$(cat "$f" 2>/dev/null || true)"
          [ -n "$name" ] || continue
          "$0" stop "$name" || true
        done
      }

      case "''${1:-}" in
        start)
          app_setup "''${2:-}" || exit 1
          # Sunshine runs `undo` only for a prep command that succeeded, so any failure after
          # the sink load must undo here. EXIT also covers `exit 1` inside a helper and errexit,
          # which a function does not inherit as an ERR trap (no `set -o errtrace`).
          start_ok=0
          trap '[ "$start_ok" = 1 ] || "$0" stop "$app_name" || true' EXIT
          # Heartbeat for the recycle timer: age of this file = minutes since the last stream.
          touch "$rt/sunshine-headless-stream-hb" 2>/dev/null || true
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

          ${lib.optionalString mangoApp ''
            # gamescope reads the file through its own env; a plain app that loads MangoHud
            # in-process must not inherit it (Steam's hooks pass it in app_env themselves).
            if [ "''${app_steam_mode:-0}" = 1 ] && [ "''${app_g[mango]:-0}" = 1 ]; then
              printf 'no_display\n' >"$rt/sunshine-mangoapp.conf"
            fi
          ''}

          client_w="''${SUNSHINE_CLIENT_WIDTH:-}"
          client_h="''${SUNSHINE_CLIENT_HEIGHT:-}"
          client_fps="''${SUNSHINE_CLIENT_FPS:-}"
          # client_hdr: 0/1 from SUNSHINE_CLIENT_HDR (forced 0 when not HDR-capable).
          client_hdr=0
          ${lib.optionalString hdr ''
            # An app with hdr = false must not advertise HDR to itself on an HDR client.
            if [ "''${app_g[hdr]:-0}" = 1 ]; then
              case "''${SUNSHINE_CLIENT_HDR:-}" in true | 1 | on) client_hdr=1 ;; esac
            fi
          ''}

          if [ -S "$rt/gamescope-0" ] && systemctl --user is-active --quiet ${gamescopeUnit}; then
            saved_params="$(cat "$rt/sunshine-headless-gamescope-params" 2>/dev/null || true)"
            saved_w="$(printf '%s' "$saved_params" | awk '{print $1}')"
            saved_h="$(printf '%s' "$saved_params" | awk '{print $2}')"
            saved_fps="$(printf '%s' "$saved_params" | awk '{print $3}')"
            saved_hdr="$(printf '%s' "$saved_params" | awk '{print $4}')"
            # A rebuilt gamescope (store path differs) must restart the stale one.
            saved_bin="$(cat "$rt/sunshine-headless-gamescope-bin" 2>/dev/null || true)"

            if [ -n "$client_w" ] && [ -n "$client_h" ] && [ -n "$client_fps" ] \
                && { [ "$saved_w" != "$client_w" ] || [ "$saved_h" != "$client_h" ] || [ "$saved_fps" != "$client_fps" ] || [ "$saved_hdr" != "$client_hdr" ] || [ "$saved_bin" != "$(gamescope_marker_now)" ]; }; then
              stop_gamescope
              start_gamescope "$client_w" "$client_h" "$client_fps" "$client_hdr"
            fi
          elif [ -n "$client_w" ] && [ -n "$client_h" ] && [ -n "$client_fps" ]; then
            start_gamescope "$client_w" "$client_h" "$client_fps" "$client_hdr"
          else
            start_gamescope "1920" "1080" "60" "$client_hdr"
          fi
          # The app's own start hook does the app-specific work (window wait, pre-kill, ...).
          app_call start || exit 1
          # Past this point the app owns the session, so the EXIT trap must not stop it.
          start_ok=1
          printf '%s' "$app_name" >"$app_active_file"
          ;;
        wait)
          app_setup "''${2:-}" || exit 1
          # Keep the desktop default off the stream/sunshine sinks (Sunshine re-defaults its own).
          last_default="$(cat "$rt/sunshine-headless-default-sink" 2>/dev/null || true)"
          iso_tick=0
          iso_warned=0
          seat_warned=0

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
                if streaming_active; then
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
              # App-specific per-tick work (window tags, baselayer, focus, ...).
              app_call tick || true
              dname="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'node.name = "\K[^"]+' || true)"
              case "$dname" in
                "$sink_name" | sink-sunshine-*)
                  [ -n "$last_default" ] && wpctl set-default "$last_default" 2>/dev/null || true
                  ;;
                "")
                  : ;;
                *)
                  # Persist the user's real-device choice so `stop` restores the last known default.
                  did="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP '^id \K[0-9]+' || true)"
                  if [ -n "$did" ] && [ "$did" != "$last_default" ]; then
                    last_default="$did"
                    printf '%s' "$last_default" >"$rt/sunshine-headless-default-sink"
                  fi
                  ;;
              esac
            else
              gone=$((gone + 1))
              [ "$gone" -ge 3 ] && break
            fi
            sleep 1
          done
          ;;
        stop)
          app_setup "''${2:-}" || exit 1
          # A paused app may be frozen: thaw first so stop doesn't wait out SIGSTOP.
          if [ "$scope_used" = 1 ] && systemctl is-active --quiet "$app_scope" 2>/dev/null; then
            systemctl thaw "$app_scope" 2>/dev/null || true
          fi
          app_call stop || true
          # Hooks need not know the file, so the verb clears it (see launch_app).
          rm -f "$app_pgid_file" "$app_active_file"

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
          # Manual recovery after a gamescope crash (the unit's ExecStopPost runs the same).
          ${drainText}
          ;;
        idle)
          # Boot-time display for the encoder probe (else 503); SDR fallback res.
          [ -S "$rt/gamescope-0" ] && systemctl --user is-active --quiet ${gamescopeUnit} && exit 0
          start_gamescope "1" "1" "1" "0"
          ;;
        recycle)
          # 30s timer: tear the session down after session.idleTimeout without a stream, and
          # regrow the probe gamescope after gamescope.regrowTimeout with no gamescope at all.
          hb="$rt/sunshine-headless-stream-hb"
          gone="$rt/sunshine-headless-gamescope-gone"
          if streaming_active; then
            touch "$hb" 2>/dev/null || true
            rm -f "$gone"
            exit 0
          fi
          now="$(date +%s)"
          hb_at="$(stat -c %Y "$hb" 2>/dev/null || echo 0)"
          age=$(( now - hb_at ))
          # A running app may override the idle timeout for its own session.
          for f in "$rt"/sunshine-headless-app-*.active; do
            [ -e "$f" ] || continue
            app_setup "$(cat "$f" 2>/dev/null || true)" 2>/dev/null || true
            break
          done
          # Nix-injected value (seconds): the fallback for a session with no active app.
          idle="''${app_idle_timeout:-${toString sessionIdleTimeout}}"
          regrow=${toString gamescopeRegrowTimeout}

          gs_active=0
          if [ -S "$rt/gamescope-0" ] && systemctl --user is-active --quiet ${gamescopeUnit}; then
            gs_active=1
          fi

          if [ "$gs_active" = 1 ]; then
            rm -f "$gone"
            # The minimal probe gamescope has nothing to tear down.
            params="$(cat "$rt/sunshine-headless-gamescope-params" 2>/dev/null || true)"
            [ "$params" = "1 1 1 0" ] && exit 0
            if [ "$idle" -gt 0 ] && [ "$age" -ge "$idle" ]; then
              recycle_stop_sessions
              stop_gamescope
            fi
            exit 0
          fi

          # No gamescope at all: clean up a session orphaned by a gamescope crash.
          if [ "$idle" -gt 0 ] && [ "$age" -ge "$idle" ]; then
            recycle_stop_sessions
          fi
          [ "$regrow" -gt 0 ] || exit 0
          # Regrow only serves the daemon's display probe; a stopped daemon opts out.
          systemctl --user is-active --quiet sunshine-headless.service || exit 0
          gone_at="$(stat -c %Y "$gone" 2>/dev/null || true)"
          if [ -z "$gone_at" ]; then
            printf '%s\n' "$now" >"$gone"
            exit 0
          fi
          if [ $(( now - gone_at )) -ge "$regrow" ]; then
            rm -f "$gone"
            start_gamescope "1" "1" "1" "0"
          fi
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
        *)
          echo "usage: sunshine-headless start <app>|wait <app>|stop <app>|drain|cleanup|idle|recycle|refresh" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  inherit sessionApp;
}
