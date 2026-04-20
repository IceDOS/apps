watchers=()
for w in cpu gpu disk network pipewire ports; do
  command -v "$w-watcher" &>/dev/null && watchers+=("$w")
done

PID=""
LAST_STATE=""

release() {
  if [[ -n "$PID" ]]; then
    kill "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null
  fi
  PID=""
}

trap 'release; exit 0' TERM INT

while :; do
  firing=()
  for w in "${watchers[@]}"; do
    [[ "$("$w-watcher")" == "true" ]] && firing+=("$w")
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

  what="sleep:shutdown"
  # inhibit idle only while pipewire has active streams
  [[ " ${firing[*]} " == *" pipewire "* ]] && what="idle:$what"
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
