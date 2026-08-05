set -euo pipefail

watchers=()
for w in cpu gpu disk network pipewire ports; do
  if command -v "$w-watcher" &>/dev/null; then
    watchers+=("$w")
  fi
done

UID_SELF="$(id -u)"

PID=""
LAST_STATE=""

release() {
  if [[ -n "$PID" ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  PID=""
}

trap 'release; exit 0' TERM INT

while :; do
  if pgrep -fU "$UID_SELF" "icedos-toggle-inhibit-(idle|sleep)" >/dev/null 2>&1; then
    if [[ -n "$PID" ]]; then
      echo "manual toggle-inhibit active, releasing watcher inhibitor: $PID"
      release
      LAST_STATE=""
    fi
    sleep 1
    continue
  fi

  firing=()
  for w in "${watchers[@]}"; do
    if [[ "$("$w-watcher" 2>/dev/null || true)" == "true" ]]; then
      firing+=("$w")
    fi
  done

  if ((${#firing[@]} == 0)); then
    if [[ -n "$PID" ]]; then
      echo "releasing inhibitor: $PID"
      release
      LAST_STATE=""
    fi
    sleep 1
    continue
  fi

  # Per-watcher contribution: pipewire → idle (keep monitors on during audio),
  # any non-pipewire watcher → sleep:shutdown (block auto-suspend during work).
  # Pipewire-only firing leaves explicit `systemctl suspend` working.
  parts=()
  if [[ " ${firing[*]} " == *" pipewire "* ]]; then
    parts+=("idle")
  fi
  for w in "${firing[@]}"; do
    if [[ "$w" != "pipewire" ]]; then
      parts+=("sleep:shutdown")
      break
    fi
  done
  what="$(
    IFS=:
    echo "${parts[*]}"
  )"
  why="failed: ${firing[*]}"
  state="$what|$why"

  if [[ "$state" != "$LAST_STATE" ]]; then
    release
    echo "inhibiting $what, $why"
    systemd-inhibit --what="$what" --why="$why" --who="sd-inhibitor" sleep infinity &
    PID=$!
    LAST_STATE="$state"
  fi

  sleep 1
done
