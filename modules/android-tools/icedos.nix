{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          lib,
          pkgs,
          ...
        }:

        let
          inherit (lib) getExe';

          adb = getExe' pkgs.android-tools "adb";

          clipboardBin =
            if pkgs ? wl-clipboard then
              "${pkgs.wl-clipboard}/bin/wl-paste"
            else if pkgs ? xclip then
              "${pkgs.xclip}/bin/xclip -o"
            else
              "";

          hasClipboard = clipboardBin != "";
        in
        {
          environment.systemPackages = [ pkgs.android-tools ];

          icedos.system.toolset.commands = [
            {
              command = "adb";
              help = "android debug bridge utilities";

              commands = [
                {
                  command = "paste";

                  script = ''
                    IP=""
                    USB=""

                    usage() {
                      echo "usage: icedos adb paste [OPTIONS] [TEXT]"
                      echo ""
                      echo "Paste text to an Android device via adb."
                      echo ""
                      echo "text source (first match wins):"
                      echo "  TEXT    paste the given argument"
                      echo "  stdin   pipe text in: echo hello | icedos adb paste"
                      ${if hasClipboard then ''echo "  default read from system clipboard (wl-paste/xclip)"'' else ""}
                      echo ""
                      echo "connection:"
                      echo "  --ip <host[:port]>  connect via TCP/IP (default port 5555)"
                      echo "  --usb <serial>      force a specific USB device serial (from 'adb devices')"
                      echo ""
                      echo "examples:"
                      echo "  icedos adb paste 'hello world'"
                      echo "  echo password | icedos adb paste"
                      echo "  icedos adb paste"
                      echo "  icedos adb paste --ip 192.168.1.50 'hello'"
                      echo "  icedos adb paste --usb ABCDEF123456 'hello'"
                    }

                    while [[ $# -gt 0 ]]; do
                      case "$1" in
                        --ip)
                          [[ $# -lt 2 ]] && die "--ip requires a host argument"
                          IP="$2"
                          shift 2
                          ;;
                        --ip=*)
                          IP="''${1#--ip=}"
                          shift
                          ;;
                        --usb)
                          [[ $# -lt 2 ]] && die "--usb requires a device serial argument"
                          USB="$2"
                          shift 2
                          ;;
                        --usb=*)
                          USB="''${1#--usb=}"
                          shift
                          ;;
                        -h|--help)
                          usage
                          exit 0
                          ;;
                        -*)
                          die "unknown flag: $1"
                          ;;
                        *)
                          TEXT="$*"
                          break
                          ;;
                      esac
                    done

                    ensure_connected() {
                      local serial_flag=""
                      [[ -n "$USB" ]] && serial_flag="-s $USB"

                      if ${adb} $serial_flag get-state >/dev/null 2>&1; then
                        return 0
                      fi

                      log_warn "no device connected"

                      if [[ -n "$IP" ]]; then
                        log_step "connecting to $IP..."
                        ${adb} connect "$IP" || die "failed to connect to $IP"
                        ${adb} wait-for-device
                      elif [[ -n "$USB" ]]; then
                        log_step "waiting for USB device $USB..."
                        ${adb} -s "$USB" wait-for-device || die "device $USB not found"
                      else
                        log_info "connect a device via USB, or pass --ip <host> / --usb <serial>"
                        read -r -p "press enter after connecting... "
                        ${adb} wait-for-device || die "no device detected"
                      fi

                      log_ok "device connected"
                    }

                    get_text() {
                      if [[ -n "''${TEXT:-}" ]]; then
                        printf '%s' "$TEXT"
                        return
                      fi

                      if ! [ -t 0 ]; then
                        cat
                        return
                      fi

                      ${
                        if hasClipboard then
                          "${clipboardBin}"
                        else
                          ''die "no text provided — pass as argument, pipe to stdin, or install wl-clipboard/xclip for clipboard support"''
                      }
                    }

                    paste() {
                      local serial_flag=""
                      [[ -n "$USB" ]] && serial_flag="-s $USB"
                      local text="$1"

                      local escaped=""
                      local i char
                      for ((i = 0; i < ''${#text}; i++)); do
                        char="''${text:$i:1}"
                        case "$char" in
                          " ") escaped+="%s" ;;
                          "%") escaped+="%%" ;;
                          "\\") escaped+="\\\\" ;;
                          "<" | ">" | "(" | ")" | "&" | "|" | ";" \
                          | '"' | "'" | "#" | "*" | "?" | "{" | "}")
                            escaped+="\\$char" ;;
                          *) escaped+="$char" ;;
                        esac
                      done

                      ${adb} $serial_flag shell input text "$escaped"
                    }

                    ensure_connected

                    text="$(get_text)" || exit 1
                    paste "$text"
                  '';

                  help = "paste text to an Android device via adb";
                }
              ];
            }
          ];
        }
      )
    ];

  meta.name = "android-tools";
}
