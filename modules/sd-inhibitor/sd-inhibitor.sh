command -v cpu-watcher &>/dev/null && CPU_WATCHER="true"
command -v disk-watcher &>/dev/null && DISK_WATCHER="true"
command -v network-watcher &>/dev/null && NETWORK_WATCHER="true"
command -v pipewire-watcher &>/dev/null && PIPEWIRE_WATCHER="true"
command -v ports-watcher &>/dev/null && PORTS_WATCHER="true"

while true; do
  [[ "$CPU_WATCHER" == "true" && `cpu-watcher` = "true" ]] && cpu="cpu " || cpu=""
  [[ "$DISK_WATCHER" == "true" && `disk-watcher` = "true" ]] && disk="disk " || disk=""
  [[ "$NETWORK_WATCHER" == "true" && `network-watcher` = "true" ]] && network="network " || network=""
  [[ "$PIPEWIRE_WATCHER" == "true" && `pipewire-watcher` = "true" ]] && pipewire="pipewire " || pipewire=""
  [[ "$PORTS_WATCHER" == "true" && `ports-watcher` = "true" ]] && ports="ports" || ports=""
  [[ "$cpu" == "" && "$disk" == "" && "$network" == "" && "$pipewire" == "" && "$ports" == "" ]] && passed="true" || passed=""

  # Skip when all watchers pass and no inhibitor is active
  [[ "$passed" == "true" && "$PID" == "" ]] && continue
  [[ "$passed" == "true" ]] && echo "killing inhibitor: $PID" && kill -9 "$PID" && PID="" && LAST_INHIBIT="" && continue

  inhibit="sleep:shutdown"

  # inhibit idle if pipewire has active inputs, outputs
  [ "$pipewire" != "" ] && inhibit="idle:$inhibit"

  [ "$LAST_INHIBIT" == "$inhibit" ] && continue
  kill -9 "$PID" &>/dev/null && PID=""

  LAST_INHIBIT="$inhibit"
  reason="failed: $cpu$disk$network$pipewire$ports"

  echo "inhibiting $inhibit, $reason"
  systemd-inhibit --what="$inhibit" --why="$reason" --who="sd-inhibitor" sh -c "while :; do sleep 1; done" &
  PID="$!"
done
