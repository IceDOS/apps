# The two runtime shell apps: the persistent idle gamescope and the Moonlight-host
# session helper wired into the Sunshine app (start/wait/stop).
{
  pkgs,
  lib,
  cfg,
  gamescopePkg,
}:

let
  inherit (pkgs) writeShellApplication;

  inherit (cfg)
    colorManagement
    hdr
    width
    height
    refresh
    renderWidth
    renderHeight
    sdrContentNits
    sdrGamutWideness
    steamOS
    upscaleFilter
    fsrSharpness
    excludeHostControllers
    isolateVirtualControllers
    ;

  # renderWidth/renderHeight empty → render at the output resolution.
  effectiveRenderWidth = if renderWidth == "" then width else renderWidth;
  effectiveRenderHeight = if renderHeight == "" then height else renderHeight;

  # Two Xwaylands (game windows land on :2); the wait-loop tagger owns focus on :1.
  # QT_QPA_PLATFORM=xcb forces Qt onto X11 (native-Wayland Qt breaks under gamescope).
  # STEAM_GAMESCOPE_HDR_SUPPORTED=1 tells Steam the gamescope session supports HDR,
  # which is what makes the HDR toggle appear in Big Picture — the gamescope-control
  # protocol reports the capability but the env var is the primary signal Steam checks.
  sessionEnv =
    "GAMESCOPE_WAYLAND_DISPLAY=gamescope-0 STEAM_MULTIPLE_XWAYLANDS=1 QT_QPA_PLATFORM=xcb "
    + lib.optionalString hdr "STEAM_GAMESCOPE_HDR_SUPPORTED=1 DXVK_HDR=1 "
    + lib.optionalString colorManagement "STEAM_GAMESCOPE_COLOR_MANAGED=1 STEAM_GAMESCOPE_COLOR_TOYS=1 ";

  # excludeHostControllers allowlist: a root systemd scope with DevicePolicy=closed
  # denies everything not listed (GPU/audio/uinput/ttys allowed, char-input/hidraw
  # never); the stream's uinput pads are allowed per-device in `wait`.
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

  idleApp = writeShellApplication {
    name = "sunshine-headless-idle";

    runtimeInputs = [
      gamescopePkg
      pkgs.wireplumber
      pkgs.coreutils
    ];

    text =
      let
        upscaleFlags =
          if upscaleFilter != "" then "-F ${upscaleFilter} --fsr-sharpness ${toString fsrSharpness} " else "";
      in
      ''
        width="''${SUNSHINE_HEADLESS_WIDTH:-${width}}"
        height="''${SUNSHINE_HEADLESS_HEIGHT:-${height}}"
        refresh="''${SUNSHINE_HEADLESS_REFRESH:-${toString refresh}}"
        render_width="''${SUNSHINE_HEADLESS_RENDER_WIDTH:-${effectiveRenderWidth}}"
        render_height="''${SUNSHINE_HEADLESS_RENDER_HEIGHT:-${effectiveRenderHeight}}"

        export ENABLE_GAMESCOPE_WSI=1

        # Record the desktop default audio sink at login, before any stream.
        rt="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        for _ in $(seq 1 30); do
          did="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP '^id \K[0-9]+' || true)"
          dname="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'node.name = "\K[^"]+' || true)"
          case "$dname" in
            "" | steam-sunshine-headless-sink | sink-sunshine-*) : ;;
            *)
              printf '%s' "$did" >"$rt/sunshine-headless-default-sink"
              break
              ;;
          esac
          sleep 1
        done

        ${lib.optionalString hdr ''
          export GAMESCOPE_PATCHED_EDID_FILE=/tmp/gamescope-patched-edid.bin
        ''}

        printf 'DISPLAY=:1\nWAYLAND_DISPLAY=gamescope-0\n' >"$rt/sunshine-headless.env"
        exec gamescope \
          --backend headless \
          --expose-wayland \
          --steam \
          --xwayland-count 2 \
          ${lib.optionalString hdr "--hdr-enabled --hdr-debug-force-output --hdr-debug-force-support --sdr-gamut-wideness ${toString sdrGamutWideness} --hdr-sdr-content-nits ${toString sdrContentNits} "} \
          ${upscaleFlags} \
          -W "$width" -H "$height" -r "$refresh" \
          -w "$render_width" -h "$render_height" \
          -- sleep infinity
      '';
  };

  sessionApp = writeShellApplication {
    name = "sunshine-headless-session";

    runtimeInputs = with pkgs; [
      coreutils
      procps
      pulseaudio # pactl: create/destroy the on-demand null-sink
      systemd # systemd-run/systemctl: cgroup device-policy scope for the injected Steam
      util-linux
      wireplumber
      xprop # tag game windows Steam left untagged so gamescope (SteamControlled) presents them
      xwininfo # enumerate top-levels on the game Xwayland
    ];

    text = ''
      rt="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      # Sunshine's own portal client runs on a private D-Bus (capture isolation); the
      # injected Steam + systemd-run scope need the REAL user session bus — reset it
      # for the whole helper (it never uses the private portal bus).
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus"
      isolate_phys=${if excludeHostControllers then "1" else "0"}
      isolate_virt=${if isolateVirtualControllers then "1" else "0"}
      steamos_args=(${if steamOS then ''"-steamos3"'' else ""})

      # Identify the `steam` belonging to THIS session by $HOME. The normal session
      # shares the desktop's $HOME but closes the desktop Steam in `start`, so it
      # matches only the injected Steam. The second session runs under a SEPARATE
      # $HOME ($2) that coexists with the still-running desktop Steam, so this
      # matches only its own Steam — `wait`/`stop` never touch the desktop one.
      sess_home="''${2:-$HOME}"
      # PIDs of the main `steam` process(es) whose $HOME is this session's. The
      # normal session matches the injected Steam (and the desktop one until it is
      # closed); the second session matches only its separate-$HOME Steam, so
      # wait/stop never touch the still-running desktop Steam.
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
      # Resolve the appid Steam LAUNCHED for a window's process: walk PID → parents to
      # the `reaper … SteamLaunch AppId=N`. Non-Steam shortcuts that re-launch a real
      # Steam game (me3 → ER Nightreign leaves the window's SteamAppId = the INNER game
      # appid) or run under SteamAppId=default (faugus → umu) give the window a wrong or
      # non-numeric appid — but the reaper's AppId is the numeric id gamescope focus AND
      # Steam's overlay/session must agree on.
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

      case "''${1:-}" in
        start)
          # On-demand stream sink: create the null-sink Sunshine captures by name
          # (audio_sink) and make it the system default, so the injected Steam —
          # which follows the default, NOT PULSE_SINK — routes into it. Created
          # per-stream so it never shows in the desktop audio UI and never hijacks
          # the default while idle; `stop` unloads it (module id recorded here). Do
          # this FIRST, before Sunshine probes audio_sink.
          if ! pactl list short sinks 2>/dev/null | grep -qw steam-sunshine-headless-sink; then
            pactl load-module module-null-sink \
              media.class=Audio/Sink \
              sink_name=steam-sunshine-headless-sink \
              channel_map=front-left,front-right \
              sink_properties='node.description="Steam Sunshine Headless Session"' \
              >"$rt/sunshine-headless-sink-module" 2>/dev/null || true
          fi
          pactl set-default-sink steam-sunshine-headless-sink 2>/dev/null || true

          # Block until the idle gamescope has started: it writes
          # sunshine-headless.env only after its initialisation, so this gate
          # guarantees gamescope-0 is up before we launch Steam into it.
          for _ in $(seq 1 300); do
            [ -f "$rt/sunshine-headless.env" ] && [ -S "$rt/gamescope-0" ] && break
            sleep 0.1
          done
          sleep 1   # let the first frame render
          # Close the desktop Steam first — NORMAL session only. Steam is
          # single-instance PER $HOME: the normal session shares the desktop's
          # $HOME, so this launch would just bounce Big Picture onto the desktop
          # (DISPLAY :0) and gamescope (:1) stays black — the desktop Steam must
          # close first. The second session ($2) runs under a SEPARATE $HOME, a
          # distinct instance that coexists with the desktop Steam, so leave the
          # desktop Steam running. `steam -shutdown` is the graceful path, but from
          # this systemd-service context steam-remote often can't reach the desktop
          # Steam's IPC pipe (ENXIO) and the shutdown silently no-ops — so escalate
          # to SIGTERM (which Steam handles as a clean shutdown) if it lingers.
          # Block until the process is fully gone.
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
          # Launch Big Picture INTO the idle gamescope (its recorded DISPLAY/
          # WAYLAND_DISPLAY); drop caps so bwrap/Steam run.
          # shellcheck disable=SC1091
          . "$rt/sunshine-headless.env"
          # Second-session HOME override: the second-session app passes its path as $2, so
          # Steam runs against a separate .steam/library/account. Empty → normal
          # HOME. Set AFTER the kill block (which shut down the real-HOME desktop
          # Steam) and only affects Steam — $rt/pactl/wpctl/dbus are HOME-independent.
          if [ -n "''${2:-}" ]; then
            # Steam needs HOME to exist + be writable or it silently fails to start
            # (black stream). Create it so a fresh second-session path just works.
            mkdir -p "$2" || true
            export HOME="$2"
          fi
          # Injected-Steam env: unified headless HDR path.
          # PULSE_SINK is a hint toward steam-sunshine-headless-sink, but Steam follows
          # the SYSTEM DEFAULT (which `start` set to that sink) — so it routes there +
          # Sunshine captures it. Kept as belt-and-suspenders for apps that honour it.
          # Per-session controller isolation. Host desktop and this headless Steam
          # are the SAME user+seat reading the SAME /dev nodes, so udev/perms can't
          # tell the readers apart — both directions are enforced at the device layer
          # on THIS launch only:
          #
          # excludeHostControllers — keep the host's real controllers out of the
          #   stream: launch Steam in a root-managed systemd SCOPE (polkit-authorized)
          #   whose cgroup device policy denies /dev/input + hidraw to the WHOLE tree
          #   (eBPF, kernel-enforced — Steam's sandbox can't escape it). `wait` allows
          #   only the stream's uinput pads back in. NB: must be a system scope; a
          #   user-level DevicePolicy is silently a no-op.
          #
          # isolateVirtualControllers — hide the Sunshine pad from the host desktop:
          #   udev strips its seat0 uaccess ACL (priority 72) so the desktop (no ACL,
          #   user not in `input`) can't open it; THIS Steam reaches it via the
          #   setgid-`input` wrapper, which promotes `input` to the real gid.
          # Run the injected Steam through the setgid-`input` shim when isolating virtual
          # controllers (to open the uaccess-stripped pad) OR under -steamos3 (so Steam runs
          # as real gid `input` and can open the input-group /dev/rfkill node → it reads/
          # controls the BT radio instead of force-disabling it; see icedos.nix rfkill rule).
          gid_wrap=()
          if [ "$isolate_virt" = 1 ] || [ "''${#steamos_args[@]}" -gt 0 ]; then
            gid_wrap=(/run/wrappers/bin/sunshine-headless-gid)
          fi

          if [ "$isolate_phys" = 1 ]; then
            # excludeHostControllers → launch Steam inside a root-managed
            # systemd SCOPE (authorized for this user by a polkit rule) with a
            # cgroup device policy that denies ALL of /dev/input + hidraw to the
            # whole tree (Steam's sandbox can't escape the cgroup). `wait` then
            # allows ONLY the stream's uinput pads back in. The scope runs as the
            # caller (--uid/--gid) and inherits the session env via the inner `env`.
            setsid systemd-run --scope --quiet --collect \
              --unit=sunshine-headless-steam.scope \
              --uid="$(id -u)" --gid="$(id -g)" \
              -p DevicePolicy=closed ${deviceAllowRunArgs} \
              -- env DISPLAY="$DISPLAY" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
                PULSE_SINK=steam-sunshine-headless-sink \
                ENABLE_GAMESCOPE_WSI=1 ${sessionEnv}\
                setpriv --inh-caps=-all --ambient-caps=-all -- \
                "''${gid_wrap[@]}" steam -gamepadui "''${steamos_args[@]}" \
              >/tmp/sunshine-headless-steam.log 2>&1 &
          else
            env DISPLAY="$DISPLAY" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
              PULSE_SINK=steam-sunshine-headless-sink \
              ENABLE_GAMESCOPE_WSI=1 ${sessionEnv}\
              setpriv --inh-caps=-all --ambient-caps=-all -- \
              setsid -f "''${gid_wrap[@]}" steam -gamepadui "''${steamos_args[@]}" >/tmp/sunshine-headless-steam.log 2>&1
          fi
          sleep 3
          ;;
        wait)
          # Desktop-default guard. Sunshine makes its OWN virtual sink
          # (sink-sunshine-stereo) the system default a few seconds after stream
          # start (#4950, no config knob). The captured apps are pinned to the
          # SEPARATE steam-sunshine-headless-sink, so we just keep the default off
          # the stream/Sunshine sinks: remember the live default when it's a real
          # device, revert to the last remembered one whenever it lands on a
          # blocklisted sink. Tracks the user's live choice; seeded from the idle
          # service's login recording.
          last_default="$(cat "$rt/sunshine-headless-default-sink" 2>/dev/null || true)"
          last_baselayer=""

          # Sunshine-tracked cmd (auto-detach=false): block while the injected Steam
          # lives, return when it exits so Sunshine ends the Moonlight session instead
          # of streaming the idle black frame. NOT `steam` itself as the cmd
          # — its bootstrap self-updates and the original PID dies (Sunshine would read
          # that as an instant exit); poll by name, scoped to this session's $HOME
          # (see session_steam_alive) so the second session ignores the desktop
          # Steam. First wait for it to come up...
          for _ in $(seq 1 60); do
            session_steam_alive && break
            sleep 0.5
          done
          # ...then block until it's been gone for 3s straight (rides the bootstrap
          # re-exec gap), running the default-sink guard each tick while Steam lives.
          gone=0
          while :; do
            if session_steam_alive; then
              gone=0
              # excludeHostControllers: the scope denies all /dev/input by
              # default; allow ONLY the stream's uinput pads back in (event/js
              # share major 13 with the host pads, so it is per-device). Recompute
              # each tick and push to the scope's DeviceAllow only when it changes.
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
              # We own gamescope focus (no -steamos3 → Steam does not manage the
              # baselayer): for each window on the game Xwayland (:2), resolve its appid
              # from the window PID's SteamAppId and tag STEAM_GAME (gamescope in
              # SteamControlled mode drops untagged windows from focus candidates), then
              # drive GAMESCOPECTRL_BASELAYER_APPID on :1 to the running game's appid so
              # gamescope presents it — reset to Steam (769) when no game window remains.
              # Uniform for Steam games, non-Steam shortcuts and emulators; launcher and
              # game share the appid, so focus follows whichever window is live.
              #
              # -steamos3: Steam tags its own games, but non-Steam shortcuts (emulators
              # like shadps4) lack a valid SteamAppId and remain untagged — gamescope
              # drops them from focus. Run a lighter tagger for those windows only; skip
              # the baselayer drive since Steam manages it natively.
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
                  # Steam handles its own games; only tag windows with no valid
                  # SteamAppId (non-Steam shortcuts / emulators like shadps4).
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
                  # Real device the user picked: remember it AND persist to the
                  # recording file (only on change) so `stop` — a separate process —
                  # restores the LAST KNOWN default, not just the login-time one.
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
          # Shut down THIS session's Steam and make sure it actually dies.
          # `steam -shutdown` is the graceful path, but from this systemd-service
          # context steam-remote often can't reach the pipe (ENXIO) and silently
          # no-ops, leaving Steam orphaned (reparented to the user manager) — so
          # escalate to SIGTERM on the session's own process(es) if it lingers.
          # Scoped by $HOME: the second session ($2) targets only its separate-$HOME
          # Steam and never touches the still-running desktop Steam.
          # Guarded on session_steam_alive: `undo`/stop normally fires AFTER this
          # session's Steam has already exited (auto-detach=false), and the
          # normal-session `steam -shutdown` is GLOBAL — firing it once the session
          # Steam is gone would kill a desktop Steam the user reopened mid-stream.
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
          # Tear down the device-policy scope (excludeHostControllers); --collect
          # also auto-reaps it once empty, this just makes it prompt.
          if [ "$isolate_phys" = 1 ]; then
            systemctl stop --quiet sunshine-headless-steam.scope 2>/dev/null || true
          fi

          # Session ending: restore the desktop's last known real default sink
          # (the wait guard keeps this file fresh as the user switches devices,
          # seeded from the login recording), then DELETE the on-demand stream
          # sink so it leaves the audio UI + stops being the default while idle.
          real="$(cat "$rt/sunshine-headless-default-sink" 2>/dev/null || true)"
          [ -n "$real" ] && wpctl set-default "$real" 2>/dev/null || true
          mod="$(cat "$rt/sunshine-headless-sink-module" 2>/dev/null || true)"
          [ -n "$mod" ] && pactl unload-module "$mod" 2>/dev/null || true
          rm -f "$rt/sunshine-headless-sink-module"
          ;;
        *)
          echo "usage: sunshine-headless-session start [HOME]|wait [HOME]|stop [HOME]" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  inherit idleApp sessionApp;
}
