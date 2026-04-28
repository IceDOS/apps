{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) mkIf;
  cfg = config.icedos;
in
{
  home-manager.sharedModules = [
    (
      { config, ... }:
      {
        home.packages =
          let
            watcher = cfg.applications.sd-inhibitor.users.${config.home.username}.watchers.gpu;
          in
          mkIf (watcher.enable) [
            (pkgs.writeShellScriptBin "gpu-watcher" ''
              THRESHOLD=${toString (watcher.threshold)}

              is_suspended() {
                [ "$(cat "$1/device/power/runtime_status" 2>/dev/null)" = "suspended" ]
              }

              nvidia_checked=0
              for card in /sys/class/drm/card[0-9] /sys/class/drm/card[0-9][0-9]; do
                [ -e "$card" ] || continue
                is_suspended "$card" && continue
                vendor=$(cat "$card/device/vendor" 2>/dev/null) || continue

                case "$vendor" in
                  0x1002)
                    [ -r "$card/device/gpu_busy_percent" ] || continue
                    util=$(cat "$card/device/gpu_busy_percent" 2>/dev/null) || continue
                    [ -n "$util" ] && (( util > THRESHOLD )) && { printf true; exit 0; }
                    ;;
                  0x10de)
                    if [ "$nvidia_checked" = 0 ] && command -v nvidia-smi >/dev/null 2>&1; then
                      nvidia_checked=1
                      max=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | sort -n | tail -1)
                      [ -n "$max" ] && (( max > THRESHOLD )) && { printf true; exit 0; }
                    fi
                    ;;
                esac
              done

              intel_cards=()
              for card in /sys/class/drm/card[0-9] /sys/class/drm/card[0-9][0-9]; do
                [ -e "$card" ] || continue
                is_suspended "$card" && continue
                [ "$(cat "$card/device/vendor" 2>/dev/null)" = "0x8086" ] || continue
                [ -d "$card/engine" ] || continue
                intel_cards+=("$card")
              done

              if (( ''${#intel_cards[@]} > 0 )); then
                declare -A t0
                for card in "''${intel_cards[@]}"; do
                  for eng in "$card"/engine/*/busy; do
                    [ -r "$eng" ] && t0["$eng"]=$(cat "$eng" 2>/dev/null)
                  done
                done
                sleep 1
                max=0
                for eng in "''${!t0[@]}"; do
                  [ -r "$eng" ] || continue
                  t1=$(cat "$eng" 2>/dev/null) || continue
                  old=''${t0[$eng]}
                  [ -z "$old" ] && continue
                  delta=$(( (t1 - old) / 10000000 ))
                  (( delta > max )) && max=$delta
                done
                (( max > THRESHOLD )) && { printf true; exit 0; }
              fi

              printf false
            '')
          ];
      }
    )
  ];
}
