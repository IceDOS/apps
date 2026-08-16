# The two runtime shell apps: the persistent idle gamescope and the Moonlight
# session helper wired into the Sunshine app (start/wait/stop).
{
  pkgs,
  lib,
  cfg,
  headlessSeat,
  gamescopePkg,
  steamPkg,
  steamosSessionSelect,
}:

let
  inherit (pkgs) writeShellApplication;

  inherit (cfg)
    colorManagement
    hdr
    renderWidth
    renderHeight
    sdrContentNits
    sdrGamutWideness
    mangoApp
    pauseOnDisconnect
    steamOS
    upscaleFilter
    fsrSharpness
    excludeHostControllers
    inputInjection
    isolateVirtualControllers
    ;

  upscaleFlags =
    if upscaleFilter != "" then "-F ${upscaleFilter} --fsr-sharpness ${toString fsrSharpness} " else "";

  # Gamescope HDR flags, applied per-stream only when the client requests HDR.
  hdrFlags = lib.optionalString hdr "--hdr-enabled --hdr-debug-force-output --hdr-debug-force-support --sdr-gamut-wideness ${toString sdrGamutWideness} --hdr-sdr-content-nits ${toString sdrContentNits} ";

  # Two Xwaylands (games land on :2); the tagger owns focus on :1. HDR env is
  # injected per-stream in the start case, not here (SDR streams stay SDR).
  sessionEnv =
    "GAMESCOPE_WAYLAND_DISPLAY=gamescope-0 STEAM_MULTIPLE_XWAYLANDS=1 QT_QPA_PLATFORM=xcb "
    + lib.optionalString colorManagement "STEAM_GAMESCOPE_COLOR_MANAGED=1 STEAM_GAMESCOPE_COLOR_TOYS=1 "
    + lib.optionalString mangoApp "STEAM_USE_MANGOAPP=1 STEAM_MANGOAPP_HORIZONTAL_SUPPORTED=1 STEAM_MANGOAPP_PRESETS_SUPPORTED=1 STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1 MANGOHUD_CONFIGFILE=\"$rt\"/sunshine-mangoapp.conf ";

  # excludeHostControllers allowlist: the scope denies everything not listed
  # (char-input/hidraw never); the stream's uinput pads are allowed per-device in `wait`.
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

  # Shadow `mangoapp` with a wrapper forcing the X11 platform: native-Wayland
  # GLFW coredumps on gamescope's minimal compositor (MangoHud #1741).
  mangoappWrapper = pkgs.writeShellScriptBin "mangoapp" ''
    unset WAYLAND_DISPLAY
    export XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 DISPLAY=:1
    exec ${pkgs.mangohud}/bin/mangoapp "$@"
  '';

  sessionApp = writeShellApplication {
    name = "sunshine-headless-session";

    runtimeInputs = [
      gamescopePkg
      # `steam` must resolve on THIS build-time PATH (systemd user services don't
      # inherit the login PATH) or the bridge cannot even resolve the target.
      steamPkg
    ]
    ++ lib.optional mangoApp mangoappWrapper
    ++ lib.optional steamOS steamosSessionSelect
    ++ (with pkgs; [
      coreutils
      gawk # awk: parse pactl output in the per-stream audio mover
      procps
      pulseaudio # pactl: create/destroy the on-demand null-sink, move game streams onto it
      systemd # systemd-run/systemctl: cgroup device-policy scope for the injected Steam
      util-linux
      wireplumber
      xprop # tag game windows Steam left untagged so gamescope (SteamControlled) presents them
      xwininfo # enumerate top-levels on the game Xwayland
    ]);

    text = ''
          rt="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          # The helper needs the REAL user session bus (not the private portal bus).
          export DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus"
          # Unset the daemon's XDG_CONFIG_HOME redirect for the whole helper: the
          # injected Steam must use $HOME/.config, not the isolated sunshine state dir.
          unset XDG_CONFIG_HOME
          isolate_phys=${if excludeHostControllers then "1" else "0"}
          isolate_virt=${if isolateVirtualControllers then "1" else "0"}
          pause=${if pauseOnDisconnect then "1" else "0"}
          # inputInjection: patched gamescope matches Sunshine's seat-suffixed passthrough
          # names exactly (fail-closed); it runs through the shim to open the /dev/input nodes.
          input_inject=${if inputInjection then "1" else "0"}
          gscope_wrap=()
          input_args=()
          if [ "$input_inject" = 1 ]; then
            gscope_wrap=(/run/wrappers/bin/sunshine-headless-gid)
            input_args=(
              --setenv=HEADLESS_INPUT_KEYBOARD="Keyboard passthrough (${headlessSeat})"
              --setenv=HEADLESS_INPUT_MOUSE="Mouse passthrough (${headlessSeat})"
              --setenv=HEADLESS_INPUT_MOUSE_ABS="Mouse passthrough (${headlessSeat}) (absolute)"
            )
          fi
          gamescope_marker="${gamescopePkg}|''${input_inject}|''${gscope_wrap[*]:-}|''${input_args[*]:-}"
          steamos_args=(${if steamOS then ''"-steamos3"'' else ""})

          # Match Steam by $HOME so wait/stop never touch a coexisting desktop/second-session Steam.
          sess_home="''${2:-$HOME}"
          session_steam_pids() {
            local p h
            for p in $(pgrep -x steam 2>/dev/null); do
              h="$(tr '\0' '\n' <"/proc/$p/environ" 2>/dev/null | sed -n 's/^HOME=//p' | head -n1 || true)"
              if [ "$h" = "$sess_home" ]; then
                printf '%s\n' "$p"
              fi
            done
          }
          session_steam_alive() {
            [ -n "$(session_steam_pids)" ]
          }
          # Resolve the appid Steam launched for a window by walking PID -> parents to the
          # reaper's AppId (SteamAppId lies for shortcuts/emulators).
          steam_launch_appid() {
            local p="$1" i cmd aid
            for i in $(seq 1 24); do
              [ -r "/proc/$p/cmdline" ] || break
              cmd="$(tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null || true)"
              aid="$(printf '%s' "$cmd" | sed -n 's/.*SteamLaunch AppId=\([0-9][0-9]*\).*/\1/p')"
              if [ -n "$aid" ]; then
                printf '%s' "$aid"
                return 0
              fi
              p="$(awk '{sub(/^.*\) /, ""); print $2}' "/proc/$p/stat" 2>/dev/null || true)"
              case "$p" in "" | 0 | 1) break ;; esac
            done
            return 1
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
          # Pin every Steam-subtree audio stream to the capture sink (default-following
          # apps escape PULSE_SINK); re-run each tick, skip streams already on target.
          route_session_audio() {
            local target sess ci pid idx sinkid
            target="$(pactl list short sinks 2>/dev/null | awk '$2=="steam-sunshine-headless-sink"{print $1; exit}')"
            [ -n "$target" ] || return 0
            sess=" $(session_steam_pids | tr '\n' ' ')"
            # Resolve sink-inputs via their pulse-client (SDL/native-PipeWire apps omit
            # application.process.id on the stream itself).
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
              pactl move-sink-input "$idx" steam-sunshine-headless-sink 2>/dev/null || true
            done < <(LC_ALL=C pactl list sink-inputs 2>/dev/null | awk '
              /^Sink Input #/ { idx=substr($3,2); sink=""; cli=""; next }
              /^[[:space:]]*Client:[[:space:]]/ { cli=$2; next }
              /^[[:space:]]*Sink:[[:space:]]/ { sink=$2; if (idx!="") print idx"\t"sink"\t"cli }')
          }

          stop_gamescope() {
            systemctl --user stop sunshine-headless-gamescope.service 2>/dev/null || true
            for _ in $(seq 1 30); do
              [ ! -S "$rt/gamescope-0" ] && break
              sleep 0.1
            done
            rm -f "$rt/gamescope-0" "$rt/sunshine-headless-gamescope-params" "$rt/sunshine-headless-gamescope-bin"
          }

          start_gamescope() {
            local w="$1" h="$2" fps="$3" hdr_on="$4"
            local rw="${toString renderWidth}" rh="${toString renderHeight}"
            [ "$rw" = "0" ] && rw="$w"
            [ "$rh" = "0" ] && rh="$h"
            local hdr_args=()
            ${lib.optionalString hdr ''[ "$hdr_on" = 1 ] && hdr_args=(${hdrFlags})''}
            printf 'DISPLAY=:1\nWAYLAND_DISPLAY=gamescope-0\n' >"$rt/sunshine-headless.env"
            printf '%s %s %s %s' "$w" "$h" "$fps" "$hdr_on" >"$rt/sunshine-headless-gamescope-params"
            # Record the gamescope store path + input-injection argv so a stale gamescope
            # (rebuild changed it) is detected and restarted in `start`.
            printf '%s' "$gamescope_marker" >"$rt/sunshine-headless-gamescope-bin"

            gamescope_env="DISPLAY=:1 ENABLE_GAMESCOPE_WSI=1 PATH=${mangoappWrapper}/bin:${gamescopePkg}/bin${lib.optionalString mangoApp " MANGOHUD_CONFIGFILE=$rt/sunshine-mangoapp.conf"}"
            # Free the transient unit first (reset-failed + stop; --collect auto-unloads):
            # a lingering leftover makes systemd-run refuse the name and abort.
            rm -f "$rt/gamescope-0"
            systemctl --user reset-failed sunshine-headless-gamescope.service 2>/dev/null || true
            systemctl --user stop sunshine-headless-gamescope.service 2>/dev/null || true
            systemd-run --user \
              --collect \
              --unit=sunshine-headless-gamescope.service \
              --property=Type=simple \
              --property=Restart=always \
              --same-dir \
              --property="Environment=$gamescope_env" \
              "''${input_args[@]}" \
              -- "''${gscope_wrap[@]}" ${gamescopePkg}/bin/gamescope \
                  --backend headless \
                  --expose-wayland \
                  --steam \
                  --xwayland-count 2 \
                  ${lib.optionalString mangoApp "--mangoapp "} \
                  "''${hdr_args[@]}" \
                  ${upscaleFlags} \
                  -W "$w" -H "$h" -r "$fps" \
                  -w "$rw" -h "$rh" \
                  -- ${pkgs.coreutils}/bin/sleep infinity

            for _ in $(seq 1 300); do
              [ -S "$rt/gamescope-0" ] && break
              sleep 0.1
            done
            sleep 1
          }

          # True while >=1 client is streaming: Sunshine's ScreenCast session on the
          # PRIVATE portal bus exists only while its video-capture thread runs (opened
          # when a session starts, Closed when the last one ends). The helper runs on
          # the real user bus, so address the private bus explicitly.
          streaming_active() {
            busctl --address="unix:path=$rt/sunshine-portal/bus" tree org.freedesktop.portal.Desktop 2>/dev/null \
              | grep -q '/session/'
          }

          case "''${1:-}" in
            start)
              # Record the pre-stream desktop default sink (restored in `stop`).
              for _ in $(seq 1 10); do
                did="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP '^id \K[0-9]+' || true)"
                dname="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'node.name = "\K[^"]+' || true)"
                case "$dname" in
                  "" | steam-sunshine-headless-sink | sink-sunshine-*) : ;;
                  *)
                    printf '%s' "$did" >"$rt/sunshine-headless-default-sink"
                    break
                    ;;
                esac
                sleep 0.2
              done

              # Create the on-demand null-sink (audio_sink) and make it the system default:
              # the injected Steam follows the default, not PULSE_SINK; `stop` unloads it.
              if ! pactl list short sinks 2>/dev/null | grep -qw steam-sunshine-headless-sink; then
                pactl load-module module-null-sink \
                  media.class=Audio/Sink \
                  sink_name=steam-sunshine-headless-sink \
                  channel_map=front-left,front-right \
                  sink_properties='node.description="Steam Sunshine Headless Session"' \
                  >"$rt/sunshine-headless-sink-module" 2>/dev/null || true
              fi
              pactl set-default-sink steam-sunshine-headless-sink 2>/dev/null || true

              ${lib.optionalString mangoApp ''
                          # Pre-set a fixed MANGOHUD_CONFIGFILE shared by gamescope's mangoapp and Steam.
                          export MANGOHUD_CONFIGFILE="$rt/sunshine-mangoapp.conf"
                          printf 'no_display\n' >"$MANGOHUD_CONFIGFILE"
              ''}

              client_w="''${SUNSHINE_CLIENT_WIDTH:-}"
              client_h="''${SUNSHINE_CLIENT_HEIGHT:-}"
              client_fps="''${SUNSHINE_CLIENT_FPS:-}"
              # steam_hdr_env: 0/1 from SUNSHINE_CLIENT_HDR (forced 0 when not HDR-capable).
              client_hdr=0
              ${lib.optionalString hdr ''case "''${SUNSHINE_CLIENT_HDR:-}" in true | 1 | on) client_hdr=1 ;; esac''}

              if [ -S "$rt/gamescope-0" ] && systemctl --user is-active --quiet sunshine-headless-gamescope.service; then
                saved_params="$(cat "$rt/sunshine-headless-gamescope-params" 2>/dev/null || true)"
                saved_w="$(printf '%s' "$saved_params" | awk '{print $1}')"
                saved_h="$(printf '%s' "$saved_params" | awk '{print $2}')"
                saved_fps="$(printf '%s' "$saved_params" | awk '{print $3}')"
                saved_hdr="$(printf '%s' "$saved_params" | awk '{print $4}')"
                # A rebuild changing the gamescope binary must restart the stale one: compare
                # the recorded store path and force a restart when it differs.
                saved_bin="$(cat "$rt/sunshine-headless-gamescope-bin" 2>/dev/null || true)"

                if [ -n "$client_w" ] && [ -n "$client_h" ] && [ -n "$client_fps" ] \
                    && { [ "$saved_w" != "$client_w" ] || [ "$saved_h" != "$client_h" ] || [ "$saved_fps" != "$client_fps" ] || [ "$saved_hdr" != "$client_hdr" ] || [ "$saved_bin" != "$gamescope_marker" ]; }; then
                  stop_gamescope
                  start_gamescope "$client_w" "$client_h" "$client_fps" "$client_hdr"
                else
                  printf 'DISPLAY=:1\nWAYLAND_DISPLAY=gamescope-0\n' >"$rt/sunshine-headless.env"
                fi
              elif [ -n "$client_w" ] && [ -n "$client_h" ] && [ -n "$client_fps" ]; then
                start_gamescope "$client_w" "$client_h" "$client_fps" "$client_hdr"
              else
                start_gamescope "1920" "1080" "60" "$client_hdr"
              fi
              # NORMAL session: close the desktop Steam first (single-instance per $HOME — else it
              # bounces onto the desktop); SIGTERM if -shutdown can't reach its pipe. Second: leave running.
              if [ -z "''${2:-}" ] && pgrep -x steam >/dev/null; then
                steam -shutdown 2>/dev/null || true
                for i in $(seq 1 60); do
                  pgrep -x steam >/dev/null || break
                  if [ "$i" -ge 16 ]; then
                    pkill -TERM -x steam 2>/dev/null || true
                  fi
                  sleep 0.25
                done
              fi
              # Launch Big Picture into the idle gamescope; drop caps so bwrap/Steam run.
              # shellcheck disable=SC1091
              . "$rt/sunshine-headless.env"
              # Second-session HOME override ($2): separate .steam/library/account; create it
              # (Steam silently fails to start if HOME doesn't exist).
              if [ -n "''${2:-}" ]; then
                mkdir -p "$2" || true
                export HOME="$2"
              fi
              # Injected-Steam env: Steam follows the system default (the stream sink); PULSE_SINK is belt-and-suspenders. Isolation: excludeHostControllers → root scope denies /dev/input+hidraw (`wait` re-allows the pads).
              # isolateVirtualControllers → pads via the setgid shim (also -steamos3/rfkill; not inputInjection — gamescope EVIOCGRABs the nodes itself).
              gid_wrap=()
              if [ "$isolate_virt" = 1 ] || [ "''${#steamos_args[@]}" -gt 0 ]; then
                gid_wrap=(/run/wrappers/bin/sunshine-headless-gid)
              fi

              # Advertise HDR to Steam only for HDR streams (STEAM_GAMESCOPE_HDR_SUPPORTED /
              # DXVK_HDR); SDR streams get neither.
              steam_hdr_env=()
              [ "$client_hdr" = 1 ] && steam_hdr_env=(STEAM_GAMESCOPE_HDR_SUPPORTED=1 DXVK_HDR=1)

              if [ "$isolate_phys" = 1 ] || [ "$pause" = 1 ]; then
                # excludeHostControllers: launch Steam inside a root-managed systemd scope
                # (polkit-authorized) whose device policy denies /dev/input + hidraw to the tree.
                # pauseOnDisconnect: same scope (plain policy) so the session can be frozen as
                # one cgroup when the last client leaves and thawed on the next connect.
                # A leftover frozen scope from a crash would make systemd-run refuse the name.
                systemctl thaw sunshine-headless-steam.scope 2>/dev/null || true
                systemctl stop --quiet sunshine-headless-steam.scope 2>/dev/null || true
                systemctl reset-failed sunshine-headless-steam.scope 2>/dev/null || true
                device_args=()
                [ "$isolate_phys" = 1 ] && device_args=(-p DevicePolicy=closed ${deviceAllowRunArgs})
                setsid systemd-run --scope --quiet --collect \
                  --unit=sunshine-headless-steam.scope \
                  --uid="$(id -u)" --gid="$(id -g)" \
                  "''${device_args[@]}" \
                  -- env DISPLAY="$DISPLAY" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
                    PULSE_SINK=steam-sunshine-headless-sink \
                    ENABLE_GAMESCOPE_WSI=1 "''${steam_hdr_env[@]}" ${sessionEnv}\
                    setpriv --inh-caps=-all --ambient-caps=-all -- \
                    "''${gid_wrap[@]}" steam -gamepadui "''${steamos_args[@]}" \
                  >"$rt"/sunshine-headless-steam.log 2>&1 &
              else
                env DISPLAY="$DISPLAY" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
                  PULSE_SINK=steam-sunshine-headless-sink \
                  ENABLE_GAMESCOPE_WSI=1 "''${steam_hdr_env[@]}" ${sessionEnv}\
                  setpriv --inh-caps=-all --ambient-caps=-all -- \
                  setsid -f "''${gid_wrap[@]}" steam -gamepadui "''${steamos_args[@]}" >"$rt"/sunshine-headless-steam.log 2>&1
              fi
              # Settle: wait for a viewable Steam window on gamescope's Xwayland (portal reports
              # the real resolution only then; early return SIGSEGV'd Sunshine on 0x0). Cap ~12s.
              for _ in $(seq 1 120); do
                steam_win=""
                while read -r w; do
                  case "$(DISPLAY=:1 xprop -id "$w" WM_CLASS 2>/dev/null)" in
                    *[Ss]team*)
                      DISPLAY=:1 xwininfo -id "$w" 2>/dev/null | grep -q IsViewable && steam_win=1 && break
                      ;;
                  esac
                done < <(DISPLAY=:1 xwininfo -root -children 2>/dev/null | grep -oE '0x[0-9a-f]+')
                [ -n "$steam_win" ] && break
                sleep 0.1
              done
              sleep 1
              ;;
            wait)
              # Desktop-default guard: Sunshine re-defaults its own sink after start; keep the
              # default off the stream/sunshine sinks, tracking the user's live choice.
              last_default="$(cat "$rt/sunshine-headless-default-sink" 2>/dev/null || true)"
              last_baselayer=""

              # Block while the injected Steam lives (auto-detach=false); poll by name scoped
              # to this session's $HOME — not the `steam` PID itself (bootstrap re-execs).
              for _ in $(seq 1 60); do
                session_steam_alive && break
                sleep 0.5
              done
              # ...then block until it's been gone 3s straight (rides the re-exec gap).
              gone=0
              frozen=0
              idle_since=""
              while :; do
                if session_steam_alive; then
                  gone=0
                  # pauseOnDisconnect: freeze the session cgroup once the last client has been
                  # gone ~10s (a stream == an open ScreenCast session on the private portal bus);
                  # thaw the moment a client is back. Only the Steam/game tree is frozen — the
                  # headless gamescope keeps running, so reconnect re-attaches instantly.
                  if [ "$pause" = 1 ]; then
                    if streaming_active; then
                      idle_since=""
                      if [ "$frozen" = 1 ]; then
                        systemctl thaw sunshine-headless-steam.scope 2>/dev/null || true
                        frozen=0
                      fi
                    else
                      [ -n "$idle_since" ] || idle_since="$(date +%s)"
                      if [ "$frozen" != 1 ] && [ "$(( $(date +%s) - idle_since ))" -ge 10 ] \
                          && systemctl is-active --quiet sunshine-headless-steam.scope 2>/dev/null; then
                        systemctl freeze sunshine-headless-steam.scope 2>/dev/null && frozen=1
                      fi
                    fi
                  fi
                  route_session_audio
                  # Recompute the scope's DeviceAllow each tick, pushing only on change.
                  if [ "$isolate_phys" = 1 ]; then
                    allow=()
                    for dd in /sys/class/input/event* /sys/class/input/js*; do
                      [ -e "$dd" ] || continue
                      case "$(readlink -f "$dd/device" 2>/dev/null)" in
                        /sys/devices/virtual/input/*) allow+=("DeviceAllow=/dev/input/$(basename "$dd") rwm") ;;
                      esac
                    done
                    cur="''${allow[*]}"
                    if [ "$cur" != "''${last_allow:-}" ]; then
                      systemctl set-property --runtime sunshine-headless-steam.scope DevicePolicy=closed ${deviceAllowSetArgs} "''${allow[@]}" >/dev/null 2>&1 || true
                      last_allow="$cur"
                    fi
                  fi
                  # Own focus: tag window appids + drive GAMESCOPECTRL_BASELAYER_APPID (reset to Steam
                  # when none). -steamos3: Steam tags its own games, so tag shortcuts only.
                  if [ "''${#steamos_args[@]}" -eq 0 ]; then
                    game_appid=""
                    while read -r w; do
                      wpid="$(DISPLAY=:2 xprop -id "$w" _NET_WM_PID 2>/dev/null | grep -oE '[0-9]+$' || true)"
                      [ -n "$wpid" ] || continue
                      a="$(tr '\0' '\n' <"/proc/$wpid/environ" 2>/dev/null | sed -n 's/^SteamAppId=//p' | head -n1 || true)"
                      case "$a" in "" | 0 | *[!0-9]*) a="$(steam_launch_appid "$wpid" || true)" ;; esac
                      case "$a" in "" | 0 | *[!0-9]*) continue ;; esac
                      if ! DISPLAY=:2 xprop -id "$w" STEAM_GAME 2>/dev/null | grep -q "= $a$"; then
                        DISPLAY=:2 xprop -id "$w" -f STEAM_GAME 32c -set STEAM_GAME "$a" 2>/dev/null || true
                      fi
                      game_appid="$a"
                    done < <(DISPLAY=:2 xwininfo -root -children 2>/dev/null | grep -oE '0x[0-9a-f]+')
                    want="''${game_appid:-769}"
                    if [ "$want" != "$last_baselayer" ]; then
                      DISPLAY=:1 xprop -root -f GAMESCOPECTRL_BASELAYER_APPID 32c \
                        -set GAMESCOPECTRL_BASELAYER_APPID "$want" 2>/dev/null || true
                      last_baselayer="$want"
                    fi
                  else
                    while read -r w; do
                      wpid="$(DISPLAY=:2 xprop -id "$w" _NET_WM_PID 2>/dev/null | grep -oE '[0-9]+$' || true)"
                      [ -n "$wpid" ] || continue
                      a="$(tr '\0' '\n' <"/proc/$wpid/environ" 2>/dev/null | sed -n 's/^SteamAppId=//p' | head -n1 || true)"
                      case "$a" in "" | 0 | *[!0-9]*) a="$(steam_launch_appid "$wpid" || true)" ;; esac
                      case "$a" in "" | 0 | *[!0-9]*) a="$wpid" ;; esac
                      if ! DISPLAY=:2 xprop -id "$w" STEAM_GAME 2>/dev/null | grep -q "= $a$"; then
                        DISPLAY=:2 xprop -id "$w" -f STEAM_GAME 32c -set STEAM_GAME "$a" 2>/dev/null || true
                      fi
                    done < <(DISPLAY=:2 xwininfo -root -children 2>/dev/null | grep -oE '0x[0-9a-f]+')
                  fi
                  dname="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'node.name = "\K[^"]+' || true)"
                  case "$dname" in
                    steam-sunshine-headless-sink | sink-sunshine-*)
                      [ -n "$last_default" ] && wpctl set-default "$last_default" 2>/dev/null || true
                      ;;
                    "")
                      : ;;
                    *)
                      # Persist the user's real-device choice (on change) so `stop` restores the
                      # last known default, not just the login-time one.
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
              # A paused session may be frozen: thaw the cgroup first so steam -shutdown /
              # SIGTERM are handled promptly and the scope stop below doesn't wait out its
              # full timeout on SIGSTOPped processes.
              systemctl is-active --quiet sunshine-headless-steam.scope 2>/dev/null \
                && systemctl thaw sunshine-headless-steam.scope 2>/dev/null || true
              # Shut down this session's Steam (by $HOME): -shutdown first, SIGTERM if it
              # lingers; guarded on session_steam_alive so it never kills a reopened desktop Steam.
              if session_steam_alive; then
                if [ -n "''${2:-}" ]; then
                  HOME="$2" steam -shutdown 2>/dev/null || true
                else
                  steam -shutdown 2>/dev/null || true
                fi
              fi
              for i in $(seq 1 60); do
                session_steam_alive || break
                if [ "$i" -ge 16 ]; then
                  for p in $(session_steam_pids); do
                    kill -TERM "$p" 2>/dev/null || true
                  done
                fi
                sleep 0.25
              done
              if [ "$isolate_phys" = 1 ] || [ "$pause" = 1 ]; then
                systemctl stop --quiet sunshine-headless-steam.scope 2>/dev/null || true
              fi

              real="$(cat "$rt/sunshine-headless-default-sink" 2>/dev/null || true)"
              [ -n "$real" ] && wpctl set-default "$real" 2>/dev/null || true
              mod="$(cat "$rt/sunshine-headless-sink-module" 2>/dev/null || true)"
              [ -n "$mod" ] && pactl unload-module "$mod" 2>/dev/null || true
              rm -f "$rt/sunshine-headless-sink-module"
              ;;
            cleanup)
              # ExecStopPost: SIGKILLed Sunshine skips `stop`, leaving the stream sink loaded+default;
              # release just the audio half (never Steam), only while a stream sink is the live default.
              dname="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'node.name = "\K[^"]+' || true)"
              case "$dname" in
                steam-sunshine-headless-sink | sink-sunshine-*)
                  real="$(cat "$rt/sunshine-headless-default-sink" 2>/dev/null || true)"
                  [ -n "$real" ] && wpctl set-default "$real" 2>/dev/null || true
                  ;;
              esac
              mod="$(cat "$rt/sunshine-headless-sink-module" 2>/dev/null || true)"
              [ -n "$mod" ] && pactl unload-module "$mod" 2>/dev/null || true
              rm -f "$rt/sunshine-headless-sink-module"
              ;;
            idle)
              # Boot-time display so the launch-time encoder probe passes (else 503); SDR
              # fallback res — the first client `start` restarts gamescope to its resolution/HDR.
              [ -S "$rt/gamescope-0" ] && systemctl --user is-active --quiet sunshine-headless-gamescope.service && exit 0
              start_gamescope "1" "1" "1" "0"
              ;;
            *)
              echo "usage: sunshine-headless-session start [HOME]|wait [HOME]|stop [HOME]|cleanup|idle" >&2
              exit 1
              ;;
          esac
    '';
  };
in
{
  inherit sessionApp;
}
