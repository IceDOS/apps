{ icedosLib, lib, ... }:

{
  options.icedos.applications.sd-inhibitor.users =
    let
      inherit (icedosLib)
        mkBoolOption
        mkNumberOption
        mkNumberListOption
        mkStrListOption
        mkSubmoduleAttrsOption
        ;

      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.users.username.applications.sd-inhibitor)
        watchers
        ;
    in
    mkSubmoduleAttrsOption { default = { }; } {
      watchers = {
        cpu =
          let
            inherit (watchers.cpu) enable threshold;
          in
          {
            enable = mkBoolOption { default = enable; };
            threshold = mkNumberOption { default = threshold; };
          };

        disk =
          let
            inherit (watchers.disk) enable threshold;
          in
          {
            enable = mkBoolOption { default = enable; };
            threshold = mkNumberOption { default = threshold; };
          };

        network =
          let
            inherit (watchers.network) enable threshold;
          in
          {
            enable = mkBoolOption { default = enable; };
            threshold = mkNumberOption { default = threshold; };
          };

        pipewire =
          let
            inherit (watchers.pipewire) enable inputsToIgnore outputsToIgnore;
          in
          {
            enable = mkBoolOption { default = enable; };
            inputsToIgnore = mkStrListOption { default = inputsToIgnore; };
            outputsToIgnore = mkStrListOption { default = outputsToIgnore; };
          };

        ports =
          let
            inherit (watchers.ports) enable inboundPorts outboundPorts;
          in
          {
            enable = mkBoolOption { default = enable; };
            inboundPorts = mkNumberListOption { default = inboundPorts; };
            outboundPorts = mkNumberListOption { default = outboundPorts; };
          };

        gpu =
          let
            inherit (watchers.gpu) enable threshold;
          in
          {
            enable = mkBoolOption { default = enable; };
            threshold = mkNumberOption { default = threshold; };
          };
      };
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
          inherit (lib)
            mkIf
            readFile
            ;

          inherit (config) icedos;
          inherit (icedos.applications) sd-inhibitor;

          sessionTargets = icedosLib.systemd.desktopSessionTargets icedos;
        in
        {
          imports = icedosLib.getModules ./modules;

          icedos.applications.toolset.commands = [
            {
              command = "toggle-inhibit";
              help = "toggle a manual systemd-inhibit (idle|sleep); --time <dur> auto-releases (e.g. 30s, 5m, 1h30m, 90 (sec), 1:30 (h:s), 1:00:00 (d:h:s)); pauses sd-inhibitor watchers while active";
              script = ''
                uid="$(id -u)"

                usage() {
                  echo "usage: icedos toggle-inhibit [idle|sleep] [--time <duration>]" >&2
                  echo "  duration forms:" >&2
                  echo "    suffix:   30s | 5m | 1h | 1h30m45s  (any combination of s/m/h tokens)" >&2
                  echo "    colon:    SS | HH:SS | DD:HH:SS     (skips minutes; use suffix for those)" >&2
                }

                # echo total seconds for the input duration, or empty string + nonzero rc on failure
                parse_duration() {
                  local input="$1"
                  local total=0

                  if [[ "$input" =~ ^([0-9]+[smh])+$ ]]; then
                    local rest="$input"
                    while [[ -n "$rest" ]]; do
                      [[ "$rest" =~ ^([0-9]+)([smh])(.*)$ ]] || return 1
                      local n="''${BASH_REMATCH[1]}"
                      local u="''${BASH_REMATCH[2]}"
                      rest="''${BASH_REMATCH[3]}"
                      case "$u" in
                        s) total=$((total + 10#$n)) ;;
                        m) total=$((total + 10#$n * 60)) ;;
                        h) total=$((total + 10#$n * 3600)) ;;
                      esac
                    done
                    echo "$total"
                    return 0
                  fi

                  if [[ "$input" =~ ^[0-9]+(:[0-9]+){0,2}$ ]]; then
                    local IFS=:
                    local -a parts
                    read -r -a parts <<<"$input"
                    case "''${#parts[@]}" in
                      1) total=$((10#''${parts[0]})) ;;
                      2) total=$((10#''${parts[0]} * 3600 + 10#''${parts[1]})) ;;
                      3) total=$((10#''${parts[0]} * 86400 + 10#''${parts[1]} * 3600 + 10#''${parts[2]})) ;;
                    esac
                    echo "$total"
                    return 0
                  fi

                  return 1
                }

                state_of() {
                  if pgrep -fU "$uid" "icedos-toggle-inhibit-$1" >/dev/null 2>&1; then
                    echo "on"
                  else
                    echo "off"
                  fi
                }

                fmt_seconds() {
                  local total="$1" d h m s
                  local -a parts=()
                  d=$((total / 86400))
                  h=$(((total % 86400) / 3600))
                  m=$(((total % 3600) / 60))
                  s=$((total % 60))
                  ((d > 0)) && parts+=("''${d}d")
                  ((h > 0)) && parts+=("''${h}h")
                  ((m > 0)) && parts+=("''${m}m")
                  ((s > 0)) && parts+=("''${s}s")
                  ((''${#parts[@]} == 0)) && parts=("0s")
                  local IFS=" "
                  echo "''${parts[*]}"
                }

                # echo "<remaining_seconds>" (rc 0), "indefinite" (rc 0), or empty (rc 1) when off
                remaining_of() {
                  local pid args etimes total rem
                  pid=$(pgrep -fU "$uid" "icedos-toggle-inhibit-$1" | head -1)
                  [[ -z "$pid" ]] && return 1
                  args=$(ps -o args= -p "$pid" 2>/dev/null)
                  etimes=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
                  [[ -z "$args" || -z "$etimes" ]] && return 1
                  if [[ "$args" =~ sleep[[:space:]]+([0-9]+) ]]; then
                    total="''${BASH_REMATCH[1]}"
                    rem=$((total - etimes))
                    ((rem < 0)) && rem=0
                    echo "$rem"
                  else
                    echo "indefinite"
                  fi
                }

                fmt_state() {
                  local s rem
                  s=$(state_of "$1")
                  if [[ "$s" != "on" ]]; then
                    echo "off"
                    return
                  fi
                  if rem=$(remaining_of "$1"); then
                    if [[ "$rem" == "indefinite" ]]; then
                      echo "on"
                    else
                      echo "on ($(fmt_seconds "$rem") left)"
                    fi
                  else
                    echo "on"
                  fi
                }

                print_states() {
                  echo "idle inhibit:  $(fmt_state idle)"
                  echo "sleep inhibit: $(fmt_state sleep)"
                }

                target=""
                duration=""
                while [[ $# -gt 0 ]]; do
                  case "$1" in
                    --time)
                      [[ $# -lt 2 ]] && { echo "--time requires a duration argument" >&2; exit 1; }
                      duration="$2"
                      shift 2
                      ;;
                    --time=*)
                      duration="''${1#--time=}"
                      shift
                      ;;
                    idle|sleep)
                      [[ -n "$target" ]] && { echo "target already set: $target" >&2; exit 1; }
                      target="$1"
                      shift
                      ;;
                    -h|--help)
                      usage
                      exit 0
                      ;;
                    *)
                      echo "unknown arg: $1" >&2
                      usage
                      exit 1
                      ;;
                  esac
                done

                if [[ -z "$target" ]]; then
                  [[ -n "$duration" ]] && { echo "--time require <idle|sleep>" >&2; exit 1; }
                  print_states
                  exit 0
                fi

                case "$target" in
                  idle) what="idle" ;;
                  sleep) what="sleep:shutdown" ;;
                esac

                seconds=""
                if [[ -n "$duration" ]]; then
                  seconds="$(parse_duration "$duration")" || {
                    echo "invalid --time \"$duration\"" >&2
                    usage
                    exit 1
                  }
                  if ((seconds == 0)); then
                    echo "--time must be greater than 0" >&2
                    exit 1
                  fi
                fi

                name="icedos-toggle-inhibit-$target"
                already_on=0
                pgrep -fU "$uid" "$name" >/dev/null 2>&1 && already_on=1

                spawn() {
                  local cmd
                  if [[ -n "$seconds" ]]; then
                    cmd=(sleep "$seconds")
                  else
                    cmd=(sleep infinity)
                  fi
                  setsid systemd-inhibit \
                    --what="$what" \
                    --who="$name" \
                    --why="manual toggle via icedos" \
                    "''${cmd[@]}" </dev/null >/dev/null 2>&1 &
                  disown
                }

                if [[ -n "$duration" ]]; then
                  # --time means "(re)arm for this duration", not toggle
                  if ((already_on)); then
                    pkill -fU "$uid" "$name"
                    for _ in 1 2 3 4 5; do
                      pgrep -fU "$uid" "$name" >/dev/null 2>&1 || break
                      sleep 0.1
                    done
                  fi
                  spawn
                  expected="on"
                else
                  if ((already_on)); then
                    pkill -fU "$uid" "$name"
                    expected="off"
                  else
                    spawn
                    expected="on"
                  fi
                fi

                # process table take a moment to settle after pkill/spawn
                for _ in 1 2 3 4 5; do
                  if [[ "$(state_of "$target")" == "$expected" ]]; then
                    break
                  fi
                  sleep 0.1
                done

                print_states
              '';
            }
          ];

          home-manager.sharedModules = [
            (
              { config, ... }:
              {
                systemd.user.services.sd-inhibitor =
                  let
                    watchers = sd-inhibitor.users.${config.home.username}.watchers;
                  in
                  mkIf
                    (
                      watchers.cpu.enable
                      || watchers.disk.enable
                      || watchers.network.enable
                      || watchers.pipewire.enable
                      || watchers.ports.enable
                      || watchers.gpu.enable
                    )
                    {
                      Unit = {
                        Description = "service to inhibit idle, sleep and shutdown based on device usage limits";
                        After = [ "graphical-session.target" ] ++ sessionTargets;
                        StartLimitIntervalSec = 60;
                        StartLimitBurst = 60;
                      };

                      Install.WantedBy = sessionTargets;

                      Service = {
                        ExecStart =
                          with pkgs;
                          "${writeShellScript "sd-inhibitor" ''
                            ${icedosLib.bash.exportSystemPath}

                            ${readFile ./sd-inhibitor.sh}
                          ''}";
                        Nice = "-20";
                        Restart = "on-failure";
                      };
                    };
              }
            )
          ];
        }
      )
    ];

  meta.name = "sd-inhibitor";
}
