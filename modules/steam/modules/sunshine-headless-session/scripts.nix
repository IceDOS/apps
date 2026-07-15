# The two runtime shell apps: the persistent idle gamescope and the Moonlight-host
# session helper wired into the Sunshine app (start/wait/stop).
{
  pkgs,
  lib,
  cfg,
  gamescopePkg,
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
    steamOS
    upscaleFilter
    fsrSharpness
    excludeHostControllers
    isolateVirtualControllers
    ;

  # Gamescope upscaler flags (-F ... --fsr-sharpness ...). Empty when no filter.
  upscaleFlags =
    if upscaleFilter != "" then "-F ${upscaleFilter} --fsr-sharpness ${toString fsrSharpness} " else "";

  # Gamescope HDR flags, applied per-stream only when the client requests HDR (see the start
  # case). Empty string when hdr is off (gamescope isn't built HDR-capable).
  hdrFlags = lib.optionalString hdr "--hdr-enabled --hdr-debug-force-output --hdr-debug-force-support --sdr-gamut-wideness ${toString sdrGamutWideness} --hdr-sdr-content-nits ${toString sdrContentNits} ";

  # Two Xwaylands (game windows land on :2); the wait-loop tagger owns focus on :1.
  # QT_QPA_PLATFORM=xcb forces Qt onto X11 (native-Wayland Qt breaks under gamescope).
  # The HDR env (STEAM_GAMESCOPE_HDR_SUPPORTED makes the HDR toggle appear in Big Picture;
  # DXVK_HDR lets games output HDR) is NOT here — it's injected per-stream in the start case
  # only when the client requests HDR, so SDR streams stay SDR (see steam_hdr_env).
  sessionEnv =
    "GAMESCOPE_WAYLAND_DISPLAY=gamescope-0 STEAM_MULTIPLE_XWAYLANDS=1 QT_QPA_PLATFORM=xcb "
    + lib.optionalString colorManagement "STEAM_GAMESCOPE_COLOR_MANAGED=1 STEAM_GAMESCOPE_COLOR_TOYS=1 "
    + lib.optionalString mangoApp "STEAM_USE_MANGOAPP=1 STEAM_MANGOAPP_HORIZONTAL_SUPPORTED=1 STEAM_MANGOAPP_PRESETS_SUPPORTED=1 STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1 MANGOHUD_CONFIGFILE=\"$rt\"/sunshine-mangoapp.conf ";

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

  # gamescope --mangoapp exec's `mangoapp` with WAYLAND_DISPLAY set, so GLFW selects the
  # Wayland platform and coredumps on gamescope's minimal compositor (libdecor "Could not get
  # required globals" -> "Glfw Error: X11: Platform not initialized", MangoHud #1741). Shadow
  # `mangoapp` with a wrapper that forces the X11 (Xwayland) platform, so glfwGetX11Display
  # works and the overlay window (GAMESCOPE_EXTERNAL_OVERLAY) is created + composited.
  mangoappWrapper = pkgs.writeShellScriptBin "mangoapp" ''
    unset WAYLAND_DISPLAY
    export XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 DISPLAY=:1
    exec ${pkgs.mangohud}/bin/mangoapp "$@"
  '';

  sessionApp = writeShellApplication {
    name = "sunshine-headless-session";

    runtimeInputs = [
      gamescopePkg
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

      # Is stream pid $1 in this session's Steam process tree? ($2 = " p1 p2 ... ")
      # Walk PID → parents (same idiom as steam_launch_appid) until a session Steam PID.
      audio_pid_in_session() {
        local p="$1"
        for _ in $(seq 1 32); do
          case "$p" in "" | 0 | 1) return 1 ;; esac
          case "$2" in *" $p "*) return 0 ;; esac
          p="$(awk '{sub(/^.*\) /, ""); print $2}' "/proc/$p/stat" 2>/dev/null || true)"
        done
        return 1
      }
      # Move every Steam-subtree audio stream onto the capture sink (native/Proton/
      # emulator), regardless of PULSE_SINK or the system default. PULSE_SINK only helps
      # apps that honour it, and the default-sink guard below deliberately keeps the
      # system default OFF the capture sink — so apps that follow the default (shadPS4,
      # many Proton titles, games launched mid-session) otherwise escape to real
      # hardware. Scoped by PID so a coexisting desktop user's audio (second session) is
      # never moved. Move by sink-input (channel-count agnostic; PipeWire re-links
      # ports). Skip streams already on target → stable streams are never re-moved (no
      # glitch); re-running each wait tick beats WirePlumber reconnect + catches new
      # games. LC_ALL=C: pactl long-format field labels are localized.
      route_session_audio() {
        local target sess ci pid idx sinkid
        target="$(pactl list short sinks 2>/dev/null | awk '$2=="steam-sunshine-headless-sink"{print $1; exit}')"
        [ -n "$target" ] || return 0
        sess=" $(session_steam_pids | tr '\n' ' ')"
        # The owning pid lives on the CLIENT object, not the sink-input node — SDL /
        # native-PipeWire apps (shadPS4) omit application.process.id on the stream. Build
        # a pulse-client-index → pid map (prefer application.process.id, fall back to the
        # daemon-set pipewire.sec.pid), then resolve each sink-input via its Client index.
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
        # HDR is per-stream: pass the --hdr-enabled flags only when this stream is HDR (and
        # gamescope was built HDR-capable, so hdrFlags is non-empty). SDR = empty = omit.
        local hdr_args=()
        ${lib.optionalString hdr ''[ "$hdr_on" = 1 ] && hdr_args=(${hdrFlags})''}
        printf 'DISPLAY=:1\nWAYLAND_DISPLAY=gamescope-0\n' >"$rt/sunshine-headless.env"
        printf '%s %s %s %s' "$w" "$h" "$fps" "$hdr_on" >"$rt/sunshine-headless-gamescope-params"
        # Record which gamescope store path this instance runs, so a later `start` can detect
        # a stale gamescope after a rebuild changed the binary and restart it (see start case).
        printf '%s' "${gamescopePkg}" >"$rt/sunshine-headless-gamescope-bin"

        gamescope_env="DISPLAY=:1 ENABLE_GAMESCOPE_WSI=1 PATH=${mangoappWrapper}/bin:${gamescopePkg}/bin${lib.optionalString mangoApp " MANGOHUD_CONFIGFILE=$rt/sunshine-mangoapp.conf"}"
        systemd-run --user \
          --unit=sunshine-headless-gamescope.service \
          --property=Type=simple \
          --property=Restart=always \
          --same-dir \
          --property="Environment=$gamescope_env" \
          -- ${gamescopePkg}/bin/gamescope \
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

      case "''${1:-}" in
        start)
          # On-demand stream sink: create the null-sink Sunshine captures by name
          # (audio_sink) and make it the system default, so the injected Steam —
          # which follows the default, NOT PULSE_SINK — routes into it. Created
          # per-stream so it never shows in the desktop audio UI and never hijacks
          # the default while idle; `stop` unloads it (module id recorded here). Do
          # this FIRST, before Sunshine probes audio_sink.
          # Record the desktop default audio sink BEFORE hijacking it so we can
          # restore it when the stream ends.
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

          # On-demand stream sink: create the null-sink Sunshine captures by name
          # (audio_sink) and make it the system default, so the injected Steam —
          # which follows the default, NOT PULSE_SINK — routes into it. Created
          # per-stream so it never shows in the desktop audio UI and never hijacks
          # the default while idle; `stop` unloads it (module id recorded here).
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
            # Share ONE mangoapp config path with the injected Steam. Steam's Quick Access ->
            # Performance level rewrites this file; mangoapp reloads it live. gamescope --mangoapp
            # only auto-creates a temp no_display config when MANGOHUD_CONFIGFILE is unset, so
            # pre-set the fixed path and seed it hidden here (both gamescope's mangoapp and Steam
            # then agree on the file).
            export MANGOHUD_CONFIGFILE="$rt/sunshine-mangoapp.conf"
            printf 'no_display\n' >"$MANGOHUD_CONFIGFILE"
          ''}

          client_w="''${SUNSHINE_CLIENT_WIDTH:-}"
          client_h="''${SUNSHINE_CLIENT_HEIGHT:-}"
          client_fps="''${SUNSHINE_CLIENT_FPS:-}"
          # HDR follows the client's Moonlight HDR toggle (SUNSHINE_CLIENT_HDR), decided
          # per-stream like resolution. Always 0/1 (never empty); forced 0 when gamescope
          # isn't built HDR-capable so the client request is ignored.
          client_hdr=0
          ${lib.optionalString hdr ''case "''${SUNSHINE_CLIENT_HDR:-}" in true | 1 | on) client_hdr=1 ;; esac''}

          if [ -S "$rt/gamescope-0" ]; then
            saved_params="$(cat "$rt/sunshine-headless-gamescope-params" 2>/dev/null || true)"
            saved_w="$(printf '%s' "$saved_params" | awk '{print $1}')"
            saved_h="$(printf '%s' "$saved_params" | awk '{print $2}')"
            saved_fps="$(printf '%s' "$saved_params" | awk '{print $3}')"
            saved_hdr="$(printf '%s' "$saved_params" | awk '{print $4}')"
            # gamescope persists across streams, so a rebuild that changes its binary leaves the
            # old one running (activation won't restart it). Compare the store path it was
            # launched from against this build's gamescope and force a restart when they differ
            # (also fires when the marker is missing → picks up the new binary on first connect).
            saved_bin="$(cat "$rt/sunshine-headless-gamescope-bin" 2>/dev/null || true)"

            if [ -n "$client_w" ] && [ -n "$client_h" ] && [ -n "$client_fps" ] \
                && { [ "$saved_w" != "$client_w" ] || [ "$saved_h" != "$client_h" ] || [ "$saved_fps" != "$client_fps" ] || [ "$saved_hdr" != "$client_hdr" ] || [ "$saved_bin" != "${gamescopePkg}" ]; }; then
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

          # Advertise HDR to the injected Steam only when this stream is HDR:
          # STEAM_GAMESCOPE_HDR_SUPPORTED shows the HDR toggle in Big Picture, DXVK_HDR lets
          # games output HDR. SDR streams get neither, so Steam/games match gamescope's SDR
          # output. Per-stream, mirrors the gamescope --hdr-enabled decision above.
          steam_hdr_env=()
          [ "$client_hdr" = 1 ] && steam_hdr_env=(STEAM_GAMESCOPE_HDR_SUPPORTED=1 DXVK_HDR=1)

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
                ENABLE_GAMESCOPE_WSI=1 "''${steam_hdr_env[@]}" ${sessionEnv}\
                setpriv --inh-caps=-all --ambient-caps=-all -- \
                "''${gid_wrap[@]}" steam -gamepadui "''${steamos_args[@]}" \
              >/tmp/sunshine-headless-steam.log 2>&1 &
          else
            env DISPLAY="$DISPLAY" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
              PULSE_SINK=steam-sunshine-headless-sink \
              ENABLE_GAMESCOPE_WSI=1 "''${steam_hdr_env[@]}" ${sessionEnv}\
              setpriv --inh-caps=-all --ambient-caps=-all -- \
              setsid -f "''${gid_wrap[@]}" steam -gamepadui "''${steamos_args[@]}" >/tmp/sunshine-headless-steam.log 2>&1
          fi
          # Deterministic settle (replaces a fixed sleep that raced): Sunshine starts
          # capturing the instant this prep-cmd `do` returns, and returning before
          # gamescope composites real content handed its rtsp handler a mid-negotiation
          # (resolution 0x0) portal stream and SIGSEGV'd it. Sunshine's ScreenCast is on
          # the private bus (its frames aren't observable here), so gate on the proxy we
          # CAN see: the injected Steam mapping a viewable window on the gamescope
          # Xwayland (:1) — i.e. gamescope is presenting real content, so the portal
          # reports the real resolution. Match WM_CLASS ~ steam (skips the mangoapp
          # overlay window). Cap ~12s so a Steam that never shows can't wedge the launch;
          # a short floor covers the first composited frame.
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
          # Desktop-default guard. Sunshine makes its OWN virtual sink
          # (sink-sunshine-stereo) the system default a few seconds after stream
          # start (#4950, no config knob). The captured apps are pinned to the
          # SEPARATE steam-sunshine-headless-sink, so we just keep the default off
          # the stream/Sunshine sinks: remember the live default when it's a real
          # device, revert to the last remembered one whenever it lands on a
          # blocklisted sink. Tracks the user's live choice; seeded from the
          # start case's login recording.
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
              route_session_audio
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
        idle)
          # Boot-time display so Sunshine's launch-time encoder probe passes (else 503).
          # Idempotent; SDR fallback res — the first client `start` restarts it to the
          # client's resolution/HDR if different.
          [ -S "$rt/gamescope-0" ] && exit 0
          start_gamescope "1" "1" "1" "0"
          ;;
        *)
          echo "usage: sunshine-headless-session start [HOME]|wait [HOME]|stop [HOME]|idle" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  inherit sessionApp;
}
