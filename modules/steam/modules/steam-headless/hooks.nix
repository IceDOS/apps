# Steam's hooks for the generic per-app session helper: the helper calls app_<slug>_<hook>
# when the app defines one, so SteamOS and desktop-Steam details stay out of that module.
{
  lib,
  steamOS,
  nativeWayland,
  colorManagement,
  mangoApp,
  steamHelpers,
}:

let
  inherit (lib) optionalString optionals;

  # Tag one window with its appid: gamescope (SteamControlled) presents Steam's appid.
  tagWindow = ''
    if ! DISPLAY=:2 xprop -id "$w" STEAM_GAME 2>/dev/null | grep -q "= $a$"; then
      DISPLAY=:2 xprop -id "$w" -f STEAM_GAME 32c -set STEAM_GAME "$a" 2>/dev/null || true
    fi
  '';

  # A game window rarely carries SteamAppId itself; Steam's reaper process does.
  windowScan = ''
    game_appid=""
    while read -r w; do
      wpid="$(DISPLAY=:2 xprop -id "$w" _NET_WM_PID 2>/dev/null | grep -oE '[0-9]+$' || true)"
      [ -n "$wpid" ] || continue
      a="$(tr '\0' '\n' <"/proc/$wpid/environ" 2>/dev/null | sed -n 's/^SteamAppId=//p' | head -n1 || true)"
      case "$a" in "" | 0 | *[!0-9]*) a="$(steam_launch_appid "$wpid" || true)" ;; esac
  '';

  windowScanEnd = ''
    done < <(DISPLAY=:2 xwininfo -root -children 2>/dev/null | grep -oE '0x[0-9a-f]+')
  '';

  # Desktop Steam: an untagged window is not a game, so skip it.
  scanDesktop = ''
    case "$a" in "" | 0 | *[!0-9]*) continue ;; esac
    ${tagWindow}
    game_appid="$a"
  '';

  # -steamos3 Steam runs the game, so an untagged window is still a game: tag it with the pid
  # as a stand-in appid, which Steam does not know and must not drive the focus check below.
  scanSteamos = ''
    real_appid=1
    case "$a" in "" | 0 | *[!0-9]*)
      a="$wpid"
      real_appid=0
      ;;
    esac
    ${tagWindow}
    if [ "$real_appid" = 1 ]; then
      game_appid="$a"
    fi
  '';

  # 769 is Steam's own appid: with no game window Steam keeps the baselayer.
  baselayerDesktop = ''
    want="''${game_appid:-769}"
    if [ "$want" != "$last_baselayer" ]; then
      DISPLAY=:1 xprop -root -f GAMESCOPECTRL_BASELAYER_APPID 32c \
        -set GAMESCOPECTRL_BASELAYER_APPID "$want" 2>/dev/null || true
      last_baselayer="$want"
    fi
  '';

  # Native-Wayland games leave no X11 window to tag, so seed the baselayer from the process.
  baselayerWayland = optionalString (nativeWayland && steamOS) ''
    # Steam may list the shortcut's appid instead of the game's, so use the exported pair.
    wl_ids="$(wayland_game_ids || true)"
    wl_appid="$(printf '%s\n' "$wl_ids" | sed -n 1p)"
    wl_launch="$(printf '%s\n' "$wl_ids" | sed -n 2p)"
    if [ -n "$wl_appid" ]; then
      game_appid="$wl_appid"
      base="$(DISPLAY=:1 xprop -root GAMESCOPECTRL_BASELAYER_APPID 2>/dev/null | sed -n 's/^.*= //p' | tr -d ' ' || true)"
      # Seed only when Steam has not listed the id (multi-app wrappers launch the real game).
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
    fi
  '';

  # A missing appid leaves the stream on Steam's black launch screen while the game runs.
  focusReroll = ''
    # Dirtying focus every 5th tick only: windows gamescope rightly rejects never reach its list.
    if [ -n "''${game_appid:-}" ] && ! game_in_focusable "$game_appid"; then
      focus_tick=$(( focus_tick + 1 ))
      if [ $(( focus_tick % 5 )) -eq 1 ]; then
        reroll_gamescope_focus
      fi
    else
      focus_tick=0
    fi
  '';

  # Steam reads these, not the generic launcher: the Deck UI, colour integration, MangoHud.
  steamEnvVars = [
    "STEAM_MULTIPLE_XWAYLANDS=1"
  ]
  ++ optionals (nativeWayland && steamOS) [ "GAMESCOPE_XWAYLAND_DISPLAY=:1" ]
  ++ optionals colorManagement [
    "STEAM_GAMESCOPE_COLOR_MANAGED=1"
    "STEAM_GAMESCOPE_COLOR_TOYS=1"
  ]
  ++ optionals mangoApp [
    "STEAM_USE_MANGOAPP=1"
    "STEAM_MANGOAPP_HORIZONTAL_SUPPORTED=1"
    "STEAM_MANGOAPP_PRESETS_SUPPORTED=1"
    "STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1"
    "MANGOHUD_CONFIGFILE=$rt/sunshine-mangoapp.conf"
  ];

  steamEnv = ''
    app_env+=(
    ${lib.concatMapStringsSep "\n" (v: ''"${v}"'') steamEnvVars}
    )
    # Advertise HDR to Steam only for HDR streams; SDR streams get neither.
    if [ "''${client_hdr:-0}" = 1 ]; then
      app_env+=("STEAM_GAMESCOPE_HDR_SUPPORTED=1" "DXVK_HDR=1")
    fi
  '';
in
{
  helpers = ''
    ${steamHelpers}
    # Resolve a window's appid by walking parent PIDs up to the reaper (SteamAppId lies).
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

    ${optionalString (nativeWayland && steamOS) ''
      # Return the native-Wayland game's exported SteamAppId plus its launch appid (a
      # shortcut may export its own id, not the real game's) so either keeps the baselayer focused.
      wl_rejected_note=
      wayland_game_ids() {
        local p a launch sess
        # Scope to this session's Steam: the sessions share one gamescope and one root window.
        sess=" $(steam_pids | tr '\n' ' ')"
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
  '';

  hooks = {
    # One Steam client per $HOME: close the desktop client, wait for its singleton FIFO to
    # release, then start Big Picture on the idle gamescope.
    start = ''
      if [ -z "$app_home" ]; then
        steam_stop
      fi
      # A write-open on the FIFO succeeds only while a reader lives (the f16a66e race).
      pipe="$sess_home/.steam/steam.pipe"
      for _ in $(seq 1 60); do
        [ -p "$pipe" ] || break
        # shellcheck disable=SC2016 # $1 is the inner bash's positional, not this script's
        if ! timeout 1 bash -c 'exec 9>"$1"' _ "$pipe" 2>/dev/null; then
          break
        fi
        sleep 0.25
      done
      app_cmd=(steam -gamepadui)
      ${optionalString steamOS "app_cmd+=(-steamos3)"}
      ${steamEnv}
      default_app_start || return 1
      # Wait for a viewable Steam window: the portal reports the real resolution only then.
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
    '';

    # Matched by $HOME, so a coexisting desktop or second-session Steam is never touched.
    alive = "steam_alive";
    pids = "steam_pids";

    # Tag window appids and drive GAMESCOPECTRL_BASELAYER_APPID.
    tick = ''
      : "''${last_baselayer:=}"
      : "''${focus_tick:=0}"
      ${windowScan}
      ${if steamOS then scanSteamos else scanDesktop}
      ${windowScanEnd}
      ${if steamOS then baselayerWayland else baselayerDesktop}
      ${focusReroll}
    '';

    stop = ''
      # A paused session is frozen and would ignore TERM.
      if [ "$scope_used" = 1 ] && systemctl is-active --quiet "$app_scope" 2>/dev/null; then
        systemctl thaw "$app_scope" 2>/dev/null || true
      fi
      steam_stop
      if [ "$scope_used" = 1 ]; then
        systemctl stop --quiet "$app_scope" 2>/dev/null || true
      fi
    '';

    # A gamescope crash must not leave this session's Steam on a dead display: only a Steam
    # launched into gamescope carries this variable, and only this session's Steam matches.
    drain = ''
      steam_alive GAMESCOPE_WAYLAND_DISPLAY gamescope-0 || return 0
      steam_stop GAMESCOPE_WAYLAND_DISPLAY gamescope-0
    '';
  };
}
