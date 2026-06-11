{ icedosLib, lib, ... }:

{
  options.icedos.applications.steam.headlessSession =
    let
      inherit (icedosLib)
        mkBoolOption
        mkEnumOption
        mkFloatBetweenOption
        mkIntBetweenOption
        mkNonEmptyStrOption
        mkStrOption
        ;
      inherit (lib) readFile;

      cfg = (fromTOML (readFile ./config.toml)).icedos.applications.steam.headlessSession;

      inherit (cfg)
        height
        excludeHostControllers
        isolateVirtualControllers
        maxNit
        normalSteamSession
        secondarySteamSession
        secondarySteamSessionPath
        output
        refresh
        renderHeight
        renderWidth
        sdrContentNits
        sdrGamutWideness
        upscaleFilter
        fsrSharpness
        width
        ;
    in
    {
      # Required + host-specific — error out if left empty.
      output = mkNonEmptyStrOption { default = output; };
      width = mkNonEmptyStrOption { default = width; };
      height = mkNonEmptyStrOption { default = height; };

      # Hide host/physical input from the injected Steam (mount-namespace mask).
      excludeHostControllers = mkBoolOption { default = excludeHostControllers; };

      # Hide the Sunshine virtual pad from the host desktop (udev drops its uaccess
      # ACL; the injected Steam reaches it via the setgid-`input` wrapper).
      isolateVirtualControllers = mkBoolOption { default = isolateVirtualControllers; };

      # Which Steam Sunshine apps to inject. normal = default HOME; second = a
      # separate account/library under secondarySteamSessionPath (required non-empty when on).
      normalSteamSession = mkBoolOption { default = normalSteamSession; };
      secondarySteamSession = mkBoolOption { default = secondarySteamSession; };
      secondarySteamSessionPath = mkStrOption { default = secondarySteamSessionPath; };

      # Gamescope render size (upscaled to width/height). Empty → render at the
      # output resolution (no upscale); the empty→output fallback is in the body.
      renderWidth = mkStrOption { default = renderWidth; };
      renderHeight = mkStrOption { default = renderHeight; };

      # SDR-on-HDR tuning: brightness (--hdr-sdr-content-nits) + gamut stretch
      # (--sdr-gamut-wideness, 0 = none .. 1 = full BT2020).
      sdrContentNits = mkIntBetweenOption {
        path = "icedos.applications.steam.headlessSession.sdrContentNits";
        source = ./config.toml;
        default = sdrContentNits;
      } 0 10000;
      sdrGamutWideness = mkFloatBetweenOption {
        path = "icedos.applications.steam.headlessSession.sdrGamutWideness";
        source = ./config.toml;
        default = sdrGamutWideness;
      } 0 1;

      # Gamescope upscaler (-F) + its sharpness (--fsr-sharpness; applies to fsr/nis).
      upscaleFilter =
        mkEnumOption
          {
            path = "icedos.applications.steam.headlessSession.upscaleFilter";
            source = ./config.toml;
            default = upscaleFilter;
          }
          [
            ""
            "fsr"
            "nis"
            "linear"
            "nearest"
            "pixel"
          ];
      fsrSharpness = mkIntBetweenOption {
        path = "icedos.applications.steam.headlessSession.fsrSharpness";
        source = ./config.toml;
        default = fsrSharpness;
      } 0 20;

      # HDR peak luminance (nit) baked into the forged EDID's static metadata.
      # 1000 = HDR10 mastering standard; clients tone-map down to their own panel.
      maxNit = mkIntBetweenOption {
        path = "icedos.applications.steam.headlessSession.maxNit";
        source = ./config.toml;
        default = maxNit;
      } 0 10000;

      # Output refresh (Hz): the single mode baked into the forged EDID
      # (width×height@refresh) AND gamescope's -r. width×height@refresh must stay
      # under the 655 MHz DTD pixel-clock ceiling (so 4K caps at 60) or the build errors.
      refresh = mkIntBetweenOption {
        path = "icedos.applications.steam.headlessSession.refresh";
        source = ./config.toml;
        default = refresh;
      } 1 360;
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:

        let
          inherit (config.icedos.applications.steam.headlessSession)
            height
            excludeHostControllers
            isolateVirtualControllers
            maxNit
            normalSteamSession
            secondarySteamSession
            secondarySteamSessionPath
            output
            refresh
            renderHeight
            renderWidth
            sdrContentNits
            sdrGamutWideness
            upscaleFilter
            fsrSharpness
            width
            ;

          inherit (lib)
            getExe
            mkDefault
            mkIf
            optional
            ;

          inherit (pkgs) callPackage writeShellApplication;

          # renderWidth/renderHeight empty → render at the output resolution.
          effectiveRenderWidth = if renderWidth == "" then width else renderWidth;
          effectiveRenderHeight = if renderHeight == "" then height else renderHeight;

          # lease-runner (wp_drm_lease client + orchestrator) + libseat-dlm.so shim:
          # run gamescope --backend drm on the leased connector.
          lease = callPackage ./lib/lease/package.nix { };

          # Payload for the setgid-`input` security.wrapper (isolateVirtualControllers):
          # a C exec shim that promotes egid `input` to the REAL gid (so bwrap mirrors
          # it into the mask sandbox), then execs its args. Binary, not a script —
          # bash would drop the setgid egid.
          gidExec = pkgs.runCommandCC "sunshine-headless-gid" { } ''
            $CC -O2 -Wall ${./lib/sunshine-headless-gid.c} -o $out
          '';

          # excludeHostControllers device allowlist (cgroup device policy — see the
          # start/wait branches). The ONLY same-user way to keep host controllers out of
          # Steam: bwrap masks don't reach Steam's FHS sandbox and uaccess is uid-keyed,
          # but a root-managed systemd SCOPE (authorized for the user via polkit) filters
          # devices kernel-side (eBPF) for the WHOLE process tree — bwrap/pressure-vessel
          # can't escape it. DevicePolicy=closed denies everything in /dev not listed here;
          # we allow GPU/audio/uinput/ttys but NEVER char-input or hidraw, so physical pads
          # are blocked. The stream's uinput pads (same major 13 as host pads) are allowed
          # per-device, dynamically, in `wait`.
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

          # Forged non-desktop HDR EDID: Valve-Index spoof (kernel non-desktop quirk)
          # + BT2020/ST2084 + maxNit, advertising the single width×height@refresh mode.
          # The build gates it on `edid-decode --check`, so a malformed EDID (or one over
          # the 655 MHz DTD ceiling) can't reach the connector.
          forgedEdid = callPackage ./lib/edid-generator/package.nix { } {
            inherit
              width
              height
              refresh
              maxNit
              ;
          };

          # Persistent IDLE gamescope on HDMI-A-1: leases the connector and drives
          # it in HDR with a minimal keep-light client — keeping it lit so its KMS
          # capture index is stable AND it exists at the Moonlight host's encoder
          # probe (at connect, before any stream). Run as a user service. The shim
          # allowlist (DLM_INPUT_ALLOW=Sunshine) only exposes Sunshine's virtual
          # pads, never the desktop KB/mouse. Steam is NOT here (stays free on the
          # desktop) — it is launched into this gamescope on demand by the prep-cmd.
          idleApp = writeShellApplication {
            name = "sunshine-headless-idle";

            runtimeInputs = [
              lease
              pkgs.gamescope
              pkgs.wireplumber
              pkgs.coreutils
            ];

            text = ''
              width="''${SUNSHINE_HEADLESS_WIDTH:-${width}}"
              height="''${SUNSHINE_HEADLESS_HEIGHT:-${height}}"
              refresh="''${SUNSHINE_HEADLESS_REFRESH:-${toString refresh}}"
              render_width="''${SUNSHINE_HEADLESS_RENDER_WIDTH:-${effectiveRenderWidth}}"
              render_height="''${SUNSHINE_HEADLESS_RENDER_HEIGHT:-${effectiveRenderHeight}}"

              export SUNSHINE_HEADLESS_OUTPUT="''${SUNSHINE_HEADLESS_OUTPUT:-${output}}"
              # Drive the GPU that hosts the forced connector. The card is implied by
              # the connector (/sys/class/drm/cardN-<output>), so derive it rather than
              # hardcode /dev/dri/cardN (the number varies per host).
              if [ -z "''${WLR_DRM_DEVICES:-}" ]; then
                for c in /sys/class/drm/card*-"$SUNSHINE_HEADLESS_OUTPUT"; do
                  [ -e "$c" ] || continue
                  WLR_DRM_DEVICES="/dev/dri/$(basename "$c" | cut -d- -f1)"
                  export WLR_DRM_DEVICES
                  break
                done
              fi
              export WLR_LIBINPUT_NO_DEVICES=1
              export DLM_INPUT_ALLOW="''${DLM_INPUT_ALLOW:-Sunshine}"
              export ENABLE_GAMESCOPE_WSI=1

              # Compositor Wayland socket for lease-runner's lease request — KWin uses
              # wayland-0, COSMIC wayland-1, etc. Auto-detect the bare wayland-N socket
              # in the runtime dir instead of hardcoding, so the lease works on any DE.
              if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
                for s in "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/wayland-[0-9]; do
                  [ -S "$s" ] || continue
                  WAYLAND_DISPLAY="$(basename "$s")"
                  export WAYLAND_DISPLAY
                  break
                done
              fi

              # Record the REAL desktop default audio sink (id) once, now — at login,
              # before any stream, while it is still the speakers. sunshine-headless-session
              # re-asserts it after Sunshine force-switches the default to its capture
              # sink (issue #4950). Retry until pipewire is up; never record the stream
              # sink itself. Runs once before the gamescope exec (this service is
              # persistent, so the id stays valid for the pipewire session).
              rt="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
              for _ in $(seq 1 30); do
                did="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP '^id \K[0-9]+' || true)"
                dname="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'node.name = "\K[^"]+' || true)"
                case "$dname" in
                  "" | steam-sunshine-headless-sink | sink-sunshine-*) : ;; # stream sink, not the real default — retry
                  *)
                    printf '%s' "$did" >"$rt/sunshine-headless-default-sink"
                    break
                    ;;
                esac
                sleep 1
              done

              # NOTE: -e (Steam-integration) stays OFF — it adds a 2nd Xwayland, swaps the
              # focus atoms to AppIDs, AND changes gamescope's scanout fb so the KMS grabber's
              # cross-fd drmModeGetFB2 could no longer import the leased plane (injected output
              # dropped from the capture list). Do NOT re-add it.
              #
              # GAME HDR is driven here, NOT by Steam. The gamescope WSI layer only
              # advertises VK_COLOR_SPACE_HDR10_ST2084_EXT to a client when the
              # GAMESCOPE_HDR_OUTPUT_FEEDBACK atom = 1 (shouldExposeHDR()):
              #   --hdr-debug-force-support → forces GAMESCOPE_HDR_OUTPUT_FEEDBACK=1
              #     (g_bForceHDRSupportDebug) so the WSI ALWAYS exposes HDR to games →
              #     the in-game HDR option appears (DXVK/native Vulkan), no Steam toggle.
              #   --hdr-debug-force-output → forces HDR10 PQ scanout (g_bForceHDR10Output)
              #     so output is deterministically HDR (no dependence on Steam env). The
              #     connector already does HDR10 (EDID has BT2020RGB+ST2084), so the
              #     forced commit takes; capture already handles HDR10 (unchanged fb).
              exec lease-runner gamescope \
                --backend drm \
                --hdr-enabled \
                --hdr-debug-force-output \
                --hdr-debug-force-support \
                --sdr-gamut-wideness ${toString sdrGamutWideness} \
                --hdr-sdr-content-nits ${toString sdrContentNits} \
                ${
                  if (upscaleFilter != "") then
                    ''-F ${upscaleFilter} --fsr-sharpness ${toString fsrSharpness} \''
                  else
                    ''\''
                }
                --expose-wayland \
                -W "$width" -H "$height" -r "$refresh" \
                -w "$render_width" -h "$render_height" \
                -- keep-light
            '';
          };

          # Moonlight-host session helper, wired into the Sunshine "Headless Stream" app:
          #   start (prep-cmd do)  — launch Steam Big Picture INTO the already-running
          #     idle gamescope (gamescope-0), dropping the inherited cap_sys_admin so
          #     bwrap/Steam run. Injected output is already lit + at a stable capture index,
          #     so there is no enumeration race.
          #   wait  (cmd, auto-detach=false) — block until the injected Steam exits, so
          #     Sunshine ends the Moonlight session (instead of streaming the idle black
          #     keep-light frame) when the user quits Steam.
          #   stop  (prep-cmd undo) — shut Steam down (the idle gamescope keeps running,
          #     connector stays lit for the next connect).
          sessionApp = writeShellApplication {
            name = "sunshine-headless-session";

            runtimeInputs = with pkgs; [
              coreutils
              procps
              pulseaudio # pactl: create/destroy the on-demand null-sink
              systemd # systemd-run/systemctl: cgroup device-policy scope for the injected Steam
              util-linux
              wireplumber
            ];

            text = ''
              rt="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
              isolate_phys=${if excludeHostControllers then "1" else "0"}
              isolate_virt=${if isolateVirtualControllers then "1" else "0"}

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

                  # Block until the idle gamescope has LIT HDMI-A-1: keep-light writes
                  # sunshine-headless.env only after its first frame commits, so this gate
                  # guarantees the connector is up before the host enumerates KMS planes
                  # (else its CRTC-descending index 0 falls through to a desktop output).
                  for _ in $(seq 1 300); do
                    [ -f "$rt/sunshine-headless.env" ] && [ -S "$rt/gamescope-0" ] && break
                    sleep 0.1
                  done
                  sleep 1   # let the first page-flip land (HDR_OUTPUT_METADATA set)
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
                  # Second-session HOME override: secondSteamApp passes the path as $2, so
                  # Steam runs against a separate .steam/library/account. Empty → normal
                  # HOME. Set AFTER the kill block (which shut down the real-HOME desktop
                  # Steam) and only affects Steam — $rt/pactl/wpctl/dbus are HOME-independent.
                  if [ -n "''${2:-}" ]; then
                    # Steam needs HOME to exist + be writable or it silently fails to start
                    # (black stream). Create it so a fresh second-session path just works.
                    mkdir -p "$2" || true
                    export HOME="$2"
                  fi
                  # Injected-Steam env, trimmed to the minimum that keeps game HDR:
                  # ENABLE_GAMESCOPE_WSI + DXVK_HDR — the WSI advertises HDR10 to the game's
                  # Vulkan surface, which IS the whole game-HDR path (Steam isn't in it; HDR
                  # is forced at gamescope via --hdr-debug-force-output/support, see idleApp).
                  # ALL STEAM_GAMESCOPE_* (HDR_SUPPORTED/COLOR_MANAGED/VIRTUAL_WHITE/
                  # FORCE_HDR_DEFAULT/FORCE_OUTPUT_TO_HDR10PQ_DEFAULT) + ENABLE_HDR_WSI were
                  # DROPPED + HDR-verified: the in-Steam HDR/color UI they fed never renders
                  # without -e; ENABLE_HDR_WSI is deprecated on Mesa 25.1+ (can wash).
                  # `-steamos3`/`-steamdeck` were tried (to surface the in-Steam HDR
                  # toggle) and SIGSEGV'd the Deck UI — it needs steamos-manager + the
                  # full gamescope-session, which conflicts with the lease/capture path.
                  # ABANDONED: game HDR does NOT need the Steam toggle — it is forced at
                  # the gamescope WSI layer (--hdr-debug-force-support, see idleApp).
                  # Steam stays plain `-gamepadui` here (stable launcher only).
                  # (-e stays OFF: it broke the KMS grabber's cross-fd capture.)
                  # DO NOT add STEAM_MULTIPLE_XWAYLANDS / STEAM_GAMESCOPE_VRR_SUPPORTED /
                  # STEAM_GAMESCOPE_HAS_TEARING_SUPPORT from the SteamOS session list:
                  # SteamOS BACKS them (gamescope --xwayland-count 2, refresh limits,
                  # adaptive-sync); here there is ONE Xwayland and a leased connector,
                  # so they are lies. MULTIPLE_XWAYLANDS made steamclient SIGSEGV in
                  # XCloseDisplay tearing down a 2nd, never-opened Display*. They add
                  # nothing toward the HDR/color UI anyway.
                  # PULSE_SINK is a hint toward steam-sunshine-headless-sink, but Steam
                  # follows the SYSTEM DEFAULT (which `start` set to that sink) — so it
                  # routes there + Sunshine captures it. Kept as belt-and-suspenders for
                  # apps that DO honour PULSE_SINK.
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
                  gid_wrap=()
                  if [ "$isolate_virt" = 1 ]; then
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
                        ENABLE_GAMESCOPE_WSI=1 DXVK_HDR=1 \
                        setpriv --inh-caps=-all --ambient-caps=-all -- \
                        "''${gid_wrap[@]}" steam -gamepadui \
                      >/tmp/sunshine-headless-steam.log 2>&1 &
                  else
                    env DISPLAY="$DISPLAY" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
                      PULSE_SINK=steam-sunshine-headless-sink \
                      ENABLE_GAMESCOPE_WSI=1 DXVK_HDR=1 \
                      setpriv --inh-caps=-all --ambient-caps=-all -- \
                      setsid -f "''${gid_wrap[@]}" steam -gamepadui >/tmp/sunshine-headless-steam.log 2>&1
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

                  # Sunshine-tracked cmd (auto-detach=false): block while the injected Steam
                  # lives, return when it exits so Sunshine ends the Moonlight session instead
                  # of streaming the idle black keep-light frame. NOT `steam` itself as the cmd
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
                  if [ -n "''${2:-}" ]; then
                    HOME="$2" steam -shutdown 2>/dev/null || true
                  else
                    steam -shutdown 2>/dev/null || true
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

          # Sunshine app injected into the host's apps.json so enabling this module is
          # self-contained — no manual apps.json entry. Merges with any other apps the
          # user declares. cmd blocks until the injected Steam exits (auto-detach=false
          # → Sunshine ends the session instead of streaming the idle keep-light frame);
          # prep-cmd lights the connector before Sunshine's KMS enumeration.
          steamApp = {
            name = "Steam";
            image-path = "steam.png";
            cmd = "${getExe sessionApp} wait";
            auto-detach = false;
            prep-cmd = [
              {
                do = "${getExe sessionApp} start";
                undo = "${getExe sessionApp} stop";
              }
            ];
          };

          # Second session: runs Steam against a separate account/library under a separate
          # $HOME (secondarySteamSessionPath, passed as $2 to ALL three verbs). Unlike the
          # normal session it does NOT close the desktop Steam — the two are distinct
          # instances that coexist (Steam is single-instance per $HOME) — so wait/stop are
          # scoped to this session's $HOME and never disturb the desktop Steam.
          secondSteamApp = {
            name = "Steam (Second Session)";
            image-path = "steam.png";
            cmd = "${getExe sessionApp} wait \"${secondarySteamSessionPath}\"";
            auto-detach = false;
            prep-cmd = [
              {
                do = "${getExe sessionApp} start \"${secondarySteamSessionPath}\"";
                undo = "${getExe sessionApp} stop \"${secondarySteamSessionPath}\"";
              }
            ];
          };
        in
        {
          hardware.display =
            let
              name = "${output}-nondesktop.bin";
            in
            {
              edid.packages = [
                (pkgs.runCommand "sunshine-headless-edid-firmware" { } ''
                  install -Dm444 ${forgedEdid}/edid.bin "$out/lib/firmware/edid/${name}"
                '')
              ];

              outputs.${output}.edid = name;
            };

          boot.kernelParams = [ "video=${output}:e" ];

          # isolateVirtualControllers: strip the seat0 uaccess ACL from the Sunshine
          # virtual pad so host desktop apps — which open evdev/js directly via that
          # ACL (the user is NOT in `input`) — can't see it. The pad stays root:input
          # 0660; only the injected Steam reaches it, via the setgid-`input` wrapper
          # below. Matches just the gamepad ("Sunshine X-Box One (virtual) pad"), not
          # the passthrough kbd/mouse. The pad is recreated per stream, rule re-applies.
          #
          # MUST be priority 72: 71-seat.rules adds the uaccess tag, 73-seat-late.rules
          # runs RUN{builtin}+="uaccess" to apply the ACL. services.udev.extraRules land
          # in 99-local.rules — too late, the ACL is already set — so ship a 72- file
          # that removes the tag in the window between 71 and 73.
          #
          # The evdev (event*) node is stripped cleanly. The legacy joydev (js*) node
          # has a race: at its add event the parent's `name` attr isn't readable yet, so
          # ATTRS{name} misses, uaccess applies, and the later tag-strip can't undo the
          # ACL — and udev/game-device defaults leave js* world-readable (0664). So also
          # force MODE 0660 (no world read) and actively clear any leftover ACL.
          services.udev.packages = mkIf isolateVirtualControllers [
            (pkgs.writeTextDir "etc/udev/rules.d/72-sunshine-headless-no-uaccess.rules" ''
              SUBSYSTEM=="input", ATTRS{name}=="Sunshine*", TAG-="uaccess", MODE="0660", RUN+="${pkgs.acl}/bin/setfacl -b $env{DEVNAME}"
            '')
          ];

          # setgid-`input` shim: gives ONLY the injected Steam (which execs through it)
          # the `input` group, so it can open the uaccess-stripped pad while the host
          # desktop (not in `input`) cannot. The setgid wrapper sets egid=input then
          # execs gidExec, which promotes it to the real gid and execs the launch.
          # Privilege is just `input` (read input devices), gated on the toggle.
          security.wrappers = mkIf isolateVirtualControllers {
            sunshine-headless-gid = {
              setgid = true;
              owner = "root";
              group = "input";
              source = "${gidExec}";
            };
          };

          # excludeHostControllers: allow a local active session to create + tune ONLY
          # the sunshine-headless-steam scope, so `start`/`wait` can run Steam under a
          # root-enforced cgroup device policy without sudo. Scoped to that single unit —
          # not blanket unit management.
          security.polkit.extraConfig = mkIf excludeHostControllers ''
            polkit.addRule(function(action, subject) {
              if (action.id == "org.freedesktop.systemd1.manage-units" &&
                  action.lookup("unit") == "sunshine-headless-steam.scope" &&
                  subject.local && subject.active) {
                return polkit.Result.YES;
              }
            });
          '';

          # Persistent idle gamescope so injected output is always lit (stable capture index,
          # present at the host's probe). lease-runner asks the compositor (KWin / cosmic-comp
          # / …) for the wp_drm_lease, auto-detecting the Wayland socket (see idleApp — KWin is
          # wayland-0, COSMIC wayland-1). Restarts until the compositor is up.
          systemd.user.services.sunshine-headless-idle = {
            description = "Persistent idle gamescope on ${output}";
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            after = [ "graphical-session.target" ];

            serviceConfig = {
              ExecStart = getExe idleApp;
              Restart = "always";
              RestartSec = "5s";
              KillSignal = "SIGKILL";
              TimeoutStopSec = "10s";
            };
          };

          environment.systemPackages = [
            lease
            idleApp
            sessionApp
          ];

          # Inject the Steam app(s) into Sunshine's apps.json (merges with the user's
          # apps; the sunshine module's empty default is {} so the lists concat).
          # normalSteamSession → default account; secondarySteamSession → secondarySteamSessionPath.
          services.sunshine.applications.apps =
            optional normalSteamSession steamApp ++ optional secondarySteamSession secondSteamApp;

          assertions = [
            {
              assertion = !secondarySteamSession || secondarySteamSessionPath != "";
              message = "icedos.applications.steam.headlessSession.secondarySteamSessionPath must be set (non-empty) when secondarySteamSession is enabled.";
            }
          ];

          # Headless KMS capture needs CAP_SYS_ADMIN + capture=kms + the leased
          # connector's plane index — provide them so the module is self-contained.
          # mkDefault → sane baseline, still user-overridable. capSysAdmin goes via the
          # icedos option (the sunshine module assigns the service option from it at
          # normal priority, so mkDefault must sit here to beat its false default);
          # the settings go via the per-key open submodule so they merge with the
          # user's other settings.
          icedos.applications.sunshine.capSysAdmin = mkDefault true;
          services.sunshine.settings.audio_sink = mkDefault "steam-sunshine-headless-sink";
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
    ];
  };
}
