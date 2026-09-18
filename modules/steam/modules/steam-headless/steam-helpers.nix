# Bash helpers shared by the session helper, the gamescope crash drain and
# steamos-session-select. Pure bash so they work without sed/grep on PATH.
''
  # steam_pids [KEY VALUE]: steam PIDs whose environ holds KEY=VALUE (default HOME=$sess_home).
  # shellcheck disable=SC2120 # KEY VALUE are optional; callers mostly use the HOME default
  steam_pids() {
    local key="''${1:-HOME}" want="''${2-''${sess_home:-}}" p v kv
    [ -n "$want" ] || return 0
    for p in $(pgrep -x steam 2>/dev/null || true); do
      v=""
      while IFS= read -r -d $'\0' kv; do
        case "$kv" in
          "$key"=*) v="''${kv#"$key"=}"; break ;;
        esac
      done 2>/dev/null <"/proc/$p/environ" || true
      [ "$v" = "$want" ] || continue
      printf '%s\n' "$p"
    done
  }
  # shellcheck disable=SC2120 # KEY VALUE are optional; callers mostly use the HOME default
  steam_alive() { [ -n "$(steam_pids "$@")" ]; }
  # steam_sig SIG [KEY VALUE]: signal matched PIDs and their process groups. Never
  # `steam -shutdown`: with the IPC listener gone it boots a fresh client.
  steam_sig() {
    local sig="$1" p pgid own
    shift
    own="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ' || true)"
    for p in $(steam_pids "$@"); do
      kill -"$sig" "$p" 2>/dev/null || true
      pgid="$(ps -o pgid= -p "$p" 2>/dev/null | tr -d ' ' || true)"
      # Skip our own group: a Steam-spawned caller would signal itself.
      case "$pgid" in "" | 0 | *[!0-9]* | "$own") ;; *) kill -"$sig" -- "-$pgid" 2>/dev/null || true ;; esac
    done
  }
  # steam_stop [KEY VALUE]: TERM, give Steam 15s to save state, then KILL stragglers.
  # shellcheck disable=SC2120 # KEY VALUE are optional; callers mostly use the HOME default
  steam_stop() {
    local i
    steam_alive "$@" || return 0
    steam_sig TERM "$@"
    for i in $(seq 1 80); do
      steam_alive "$@" || return 0
      [ "$i" -ge 60 ] && steam_sig KILL "$@"
      sleep 0.25
    done
  }
''
