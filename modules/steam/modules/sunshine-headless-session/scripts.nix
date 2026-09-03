# Runtime shell apps: the persistent idle gamescope and the Sunshine session helper.
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
    nativeWayland
    pauseOnDisconnect
    steamOS
    upscaleFilter
    fsrSharpness
    excludeHostControllers
    inputInjection
    isolateVirtualControllers
    realtime
    secondarySteamSession
    secondarySteamSessionPath
    sessionIdleTimeout
    gamescopeRegrowTimeout
    ;

  upscaleFlags =
    if upscaleFilter != "" then "-F ${upscaleFilter} --fsr-sharpness ${toString fsrSharpness} " else "";

  # Gamescope HDR flags, applied per-stream only when the client requests HDR.
  hdrFlags = lib.optionalString hdr "--hdr-enabled --hdr-debug-force-output --hdr-debug-force-support --sdr-gamut-wideness ${toString sdrGamutWideness} --hdr-sdr-content-nits ${toString sdrContentNits} ";

  # Two Xwaylands (:2 games, :1 tagger); HDR env injected per-stream in `start`.
  # PATH names helpers (proton-launch, me3); PROTON_LAUNCH_LOG keeps the child's stdio on /dev/null.
  sessionEnv =
    "PATH=\"$steam_path\" PROTON_LAUNCH_LOG=\"$rt\"/proton-launch.log "
    + "GAMESCOPE_WAYLAND_DISPLAY=gamescope-0 STEAM_MULTIPLE_XWAYLANDS=1 "
    + lib.optionalString (!nativeWayland) "QT_QPA_PLATFORM=xcb "
    # GAMESCOPE_XWAYLAND_DISPLAY: with STEAM_MULTIPLE_XWAYLANDS=1 Steam's runtime client
    # (not launcher/gamescope) picks its X display here; only in nativeWayland && steamOS mode.
    + lib.optionalString (nativeWayland && steamOS) "GAMESCOPE_XWAYLAND_DISPLAY=:1 "
    + lib.optionalString colorManagement "STEAM_GAMESCOPE_COLOR_MANAGED=1 STEAM_GAMESCOPE_COLOR_TOYS=1 "
    + lib.optionalString mangoApp "STEAM_USE_MANGOAPP=1 STEAM_MANGOAPP_HORIZONTAL_SUPPORTED=1 STEAM_MANGOAPP_PRESETS_SUPPORTED=1 STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1 MANGOHUD_CONFIGFILE=\"$rt\"/sunshine-mangoapp.conf ";

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

  sessionApp = writeShellApplication {
    name = "sunshine-headless-session";

    runtimeInputs = [
      gamescopePkg
      # `steam` must resolve on this build-time PATH (user services don't inherit login PATH).
      steamPkg
    ]
    ++ lib.optional mangoApp mangoappWrapper
    ++ lib.optional steamOS steamosSessionSelect
    ++ (with pkgs; [
      coreutils
      gawk # awk: parse pactl output in the per-stream audio mover
      acl # getfacl: verify headless pads are uaccess-stripped
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
      # Unset the daemon's XDG_CONFIG_HOME redirect: Steam uses $HOME/.config, not the isolated state dir.
      unset XDG_CONFIG_HOME
      isolate_phys=${if excludeHostControllers then "1" else "0"}
      isolate_virt=${if isolateVirtualControllers then "1" else "0"}
      pause=${if pauseOnDisconnect then "1" else "0"}
      # inputInjection: patched gamescope matches the seat-suffixed passthrough names (fail-closed).
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
      # gamescope always runs through the cap_sys_nice wrapper (SetNice(-20); --rt adds
      # realtime). Wrapper is exec'd by the gid shim when inputInjection is on.
      gamescope_wrapper=(/run/wrappers/bin/sunshine-headless-gamescope)
      gamescope_marker="${gamescopePkg}|''${input_inject}|${if realtime then "1" else "0"}|''${gamescope_wrapper[*]}|''${gscope_wrap[*]:-}|''${input_args[*]:-}"
      steamos_args=(${if steamOS then ''"-steamos3"'' else ""})

      # Only these install a 72-sunshine-headless-*-no-uaccess.rules udev rule, so only
      # they have uaccess stripping worth verifying; steamOS alone adds none.
      bridge_needed=0
      [ "$isolate_virt" = 1 ] && bridge_needed=1
      [ "$input_inject" = 1 ] && bridge_needed=1

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
      # Resolve a window's appid via PID->parent walk to the reaper (SteamAppId lies).
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

      ${lib.optionalString (nativeWayland && steamOS) ''
        # Return the native-Wayland game's exported SteamAppId plus its launch appid (a
        # shortcut may export its own id, not the real game's) so the baselayer stays focused for either.
        wl_rejected_note=
        wayland_game_ids() {
          local p a launch sess
          # Scope to this session's Steam (the normal/secondary sessions share one
          # gamescope and one root window), matching route_session_audio's pattern.
          sess=" $(session_steam_pids | tr '\n' ' ')"
          for p in /proc/[0-9]*; do
            grep -qz '^PROTON_ENABLE_WAYLAND=1$' "$p/environ" 2>/dev/null || continue
            tr '\0' '\n' <"$p/environ" 2>/dev/null | grep -q '^DISPLAY=.' && continue
            if ! audio_pid_in_session "''${p##*/}" "$sess"; then
              if [ "''${wl_rejected_note:-0}" != 1 ]; then
                wl_rejected_note=1
                # Rejected as not-attributable to this session; can also be an in-session
                # proc whose parent chain no longer reaches this session's steam pid.
                echo "sunshine-headless: skipped native-Wayland proc ''${p##*/} (not attributable to this session)" >&2
              fi
              continue
            fi
            a="$(tr '\0' '\n' <"$p/environ" 2>/dev/null | sed -n 's/^SteamAppId=//p' | head -n1 || true)"
            case "$a" in "" | 0 | *[!0-9]*) continue ;; esac
            launch="$(steam_launch_appid "''${p##*/}" || true)"
            case "$launch" in "" | 0 | *[!0-9]*) launch="" ;; esac
            printf '%s\n%s\n' "$a" "$launch"
            return 0
          done
          return 1
        }
      ''}

      audio_pid_in_session() {
        local p="$1"
        for _ in $(seq 1 32); do
          case "$p" in "" | 0 | 1) return 1 ;; esac
          case "$2" in *" $p "*) return 0 ;; esac
          p="$(awk '{sub(/^.*\) /, ""); print $2}' "/proc/$p/stat" 2>/dev/null || true)"
        done
        return 1
      }
      # Verify the input bridge actually held: virtual streaming devices must carry the
      # seat marker, and (when isolation is on) be uaccess-stripped so the human user can't
      # open them without the shim. Warn once on any leak; never blocks streaming.
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
      # Pin Steam-subtree audio to the capture sink (default-following apps escape PULSE_SINK).
      route_session_audio() {
        local target sess ci pid idx sinkid
        target="$(pactl list short sinks 2>/dev/null | awk '$2=="steam-sunshine-headless-sink"{print $1; exit}')"
        [ -n "$target" ] || return 0
        sess=" $(session_steam_pids | tr '\n' ' ')"
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
        # Record the gamescope store path + argv so a stale one is restarted in `start`.
        printf '%s' "$gamescope_marker" >"$rt/sunshine-headless-gamescope-bin"

        gamescope_env="DISPLAY=:1 ENABLE_GAMESCOPE_WSI=1 PATH=${mangoappWrapper}/bin:${gamescopePkg}/bin${lib.optionalString mangoApp " MANGOHUD_CONFIGFILE=$rt/sunshine-mangoapp.conf"}"

        # Free the transient unit first: a leftover makes systemd-run refuse the name.
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
          -- "''${gscope_wrap[@]}" "''${gamescope_wrapper[@]}" ${if realtime then "--rt" else ""} \
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
        # Surface a launch failure instead of streaming a black frame (previously silent).
        if [ ! -S "$rt/gamescope-0" ]; then
          echo "sunshine-headless: gamescope-0 never appeared within 30s of start_gamescope -W $w -H $h -r $fps (see: journalctl --user -u sunshine-headless-gamescope.service)" >&2
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

      # Recycle teardown: the full `stop` path per session HOME (idempotent; Sunshine's
      # own undo may race in and re-run it, which is a no-op).
      recycle_stop_sessions() {
        "$0" stop
        ${lib.optionalString secondarySteamSession ''"$0" stop "${secondarySteamSessionPath}"''}
      }

      case "''${1:-}" in
        start)
          # Heartbeat for the recycle timer: age of this file = minutes since the last stream.
          touch "$rt/sunshine-headless-stream-hb" 2>/dev/null || true
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

          # On-demand null-sink as system default (Steam follows it); `stop` unloads it.
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
            # A rebuilt gamescope (store path differs) must restart the stale one.
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
          # NORMAL session: close the desktop Steam first (single-instance per $HOME);
          # SIGTERM if -shutdown can't reach its pipe. Second session: leave it running.
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
          # Wait for Steam's singleton FIFO ($HOME/.steam/steam.pipe) to release before
          # launching: a write-open succeeds only while a reader lives (the f16a66e race).
          pipe="$HOME/.steam/steam.pipe"
          [ -n "''${2:-}" ] && pipe="$2/.steam/steam.pipe"
          for i in $(seq 1 60); do
            [ -p "$pipe" ] || break
            # shellcheck disable=SC2016 # $1 is the inner bash's positional, not this script's
            if ! timeout 1 bash -c 'exec 9>"$1"' _ "$pipe" 2>/dev/null; then
              break
            fi
            sleep 0.25
          done
          # Launch Big Picture into the idle gamescope; drop caps so bwrap/Steam run.
          # shellcheck disable=SC1091
          . "$rt/sunshine-headless.env"
          # Second-session HOME override ($2): separate account; create it (Steam fails if absent).
          if [ -n "''${2:-}" ]; then
            mkdir -p "$2" || true
            export HOME="$2"
          fi
          # /etc/profiles is invisible in Steam's FHS bwrap (/etc is tmpfs); /run and /home
          # are bound. Append, so the session's own store dirs still win for `steam`.
          steam_path="$PATH:/run/wrappers/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
          # Injected-Steam env: follows the system default (stream sink); PULSE_SINK is belt-and-suspenders.
          # Isolation: excludeHostControllers = root scope; isolateVirtualControllers = setgid shim.
          gid_wrap=()
          if [ "$isolate_virt" = 1 ] || [ "''${#steamos_args[@]}" -gt 0 ]; then
            gid_wrap=(/run/wrappers/bin/sunshine-headless-gid)
          fi

          # Advertise HDR to Steam only for HDR streams; SDR streams get neither.
          steam_hdr_env=()
          [ "$client_hdr" = 1 ] && steam_hdr_env=(STEAM_GAMESCOPE_HDR_SUPPORTED=1 DXVK_HDR=1)

          if [ "$isolate_phys" = 1 ] || [ "$pause" = 1 ]; then
            # excludeHostControllers: root-managed scope denying /dev/input+hidraw.
            # pauseOnDisconnect: same scope (plain policy) so the tree freezes/thaws as one cgroup.
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
          # Wait for a viewable Steam window (the portal reports real resolution only then).
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
          # Keep the desktop default off the stream/sunshine sinks (Sunshine re-defaults its own).
          last_default="$(cat "$rt/sunshine-headless-default-sink" 2>/dev/null || true)"
          last_baselayer=""
          iso_tick=0
          iso_warned=0
          seat_warned=0

          # Block while the injected Steam lives (poll by $HOME-scoped name, not PID: bootstrap re-execs).
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
              # Throttled input-isolation check; warn once when a virtual device escaped.
              iso_tick=$(( iso_tick + 1 ))
              if [ $(( iso_tick % 15 )) -eq 1 ] && [ "''${iso_warned:-0}" != 1 ] && ! verify_input_isolation; then
                iso_warned=1
              fi
              # pauseOnDisconnect: freeze the Steam/game tree ~10s after the last client
              # leaves, thaw on reconnect (gamescope keeps running).
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
                # inputtino uses uhid (pads) and uinput (kbd/mouse), so match any virtual
                # parent -- plus the pads' hidraw nodes, which Steam Input reads.
                for dd in /sys/class/input/event* /sys/class/input/js* /sys/class/hidraw/hidraw*; do
                  [ -e "$dd" ] || continue
                  case "$(readlink -f "$dd/device" 2>/dev/null)" in
                    /sys/devices/virtual/*) ;;
                    *) continue ;;
                  esac
                  case "$dd" in
                    */hidraw*) allow+=("DeviceAllow=/dev/$(basename "$dd") rwm") ;;
                    *) allow+=("DeviceAllow=/dev/input/$(basename "$dd") rwm") ;;
                  esac
                done
                cur="''${allow[*]}"
                if [ "$cur" != "''${last_allow:-}" ]; then
                  # Never silence this: a denied set-property means the pads stay blocked
                  # and Steam sees no controller at all. Log the transition, keep retrying.
                  if systemctl set-property --runtime sunshine-headless-steam.scope \
                      DevicePolicy=closed ${deviceAllowSetArgs} "''${allow[@]}" >/dev/null 2>&1; then
                    last_allow="$cur"
                    allow_failed=0
                  elif [ "''${allow_failed:-0}" != 1 ]; then
                    echo "sunshine-headless: DeviceAllow refresh on sunshine-headless-steam.scope failed; Moonlight controllers will not reach Steam" >&2
                    allow_failed=1
                  fi
                fi
              fi
              # Tag window appids + drive GAMESCOPECTRL_BASELAYER_APPID (reset to Steam when none).
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

                ${lib.optionalString (nativeWayland && steamOS) ''
                  # Steam only reorders the baselayer for X11 windows it can see, and may list
                  # the shortcut's appid instead of the game's, so drive it from the process.
                  wl_ids="$(wayland_game_ids || true)"
                  wl_appid="$(printf '%s\n' "$wl_ids" | sed -n 1p)"
                  wl_launch="$(printf '%s\n' "$wl_ids" | sed -n 2p)"
                  if [ -n "$wl_appid" ]; then
                    base="$(DISPLAY=:1 xprop -root GAMESCOPECTRL_BASELAYER_APPID 2>/dev/null | sed -n 's/^.*= //p' | tr -d ' ' || true)"
                    # Seed the game's exported id only when Steam hasn't listed it (multi-app
                    # wrappers launch the real game); else let Steam's own reordering drive focus.
                    if [[ ",$base," != *",$wl_appid,"* ]]; then
                      desired="$wl_appid"
                      if [ -n "$wl_launch" ] && [ "$wl_launch" != "$wl_appid" ]; then
                        desired="$desired,$wl_launch"
                      fi
                      rest="$(printf '%s' "$base" | tr ',' '\n' | grep -vx "$wl_appid" | grep -vx "$wl_launch" | tr '\n' ',' | sed 's/,$//' || true)"
                      [ -n "$rest" ] && rest=",$rest"
                      if [ "$base" != "$desired$rest" ]; then
                        DISPLAY=:1 xprop -root -f GAMESCOPECTRL_BASELAYER_APPID 32c \
                          -set GAMESCOPECTRL_BASELAYER_APPID "$desired$rest" 2>/dev/null || true
                      fi
                    fi
                  fi''}
              fi

              dname="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'node.name = "\K[^"]+' || true)"
              case "$dname" in
                steam-sunshine-headless-sink | sink-sunshine-*)
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
          # A paused session may be frozen: thaw first so shutdown/stop don't wait out SIGSTOP.
          systemctl is-active --quiet sunshine-headless-steam.scope 2>/dev/null \
            && systemctl thaw sunshine-headless-steam.scope 2>/dev/null || true
          # Shut down this session's Steam (by $HOME): -shutdown first, SIGTERM if it lingers.
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
          # SIGKILLed Sunshine skips `stop`: release just the audio half (never Steam).
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
          # Boot-time display for the encoder probe (else 503); SDR fallback res.
          [ -S "$rt/gamescope-0" ] && systemctl --user is-active --quiet sunshine-headless-gamescope.service && exit 0
          start_gamescope "1" "1" "1" "0"
          ;;
        recycle)
          # 30s timer: tear the session down after sessionIdleTimeout without a stream,
          # and regrow the minimal probe gamescope after gamescopeRegrowTimeout with
          # no gamescope at all (teardown, crash, or manual stop).
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
          # Nix-injected values (seconds): assigned here so shellcheck sees them.
          idle=${toString sessionIdleTimeout}
          regrow=${toString gamescopeRegrowTimeout}

          gs_active=0
          if [ -S "$rt/gamescope-0" ] && systemctl --user is-active --quiet sunshine-headless-gamescope.service; then
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
        *)
          echo "usage: sunshine-headless-session start [HOME]|wait [HOME]|stop [HOME]|cleanup|idle|recycle" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  inherit sessionApp;
}
