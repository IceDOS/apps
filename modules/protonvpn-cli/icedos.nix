{ icedosLib, lib, ... }:

{
  options.icedos.applications.protonvpn-cli =
    let
      inherit (icedosLib)
        mkBoolOption
        mkStrListOption
        mkStrOption
        ;

      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.protonvpn-cli)
        connect
        desktopEntry
        settings
        ;
    in
    {
      connect = {
        country = mkStrOption { default = connect.country; };
        city = mkStrOption { default = connect.city; };
        p2p = mkBoolOption { default = connect.p2p; };
        securecore = mkBoolOption { default = connect.securecore; };
        tor = mkBoolOption { default = connect.tor; };
        random = mkBoolOption { default = connect.random; };
      };

      desktopEntry = {
        enable = mkBoolOption { default = desktopEntry.enable; };
        countries = mkStrListOption { default = desktopEntry.countries; };
      };

      settings = {
        netshield = {
          malware = mkBoolOption { default = settings.netshield.malware; };
          full = mkBoolOption { default = settings.netshield.full; };
        };

        killSwitch = mkBoolOption { default = settings.killSwitch; };
        portForwarding = mkBoolOption { default = settings.portForwarding; };
        customDns = mkBoolOption { default = settings.customDns; };
        customDnsServers = mkStrOption { default = settings.customDnsServers; };
        vpnAccelerator = mkBoolOption { default = settings.vpnAccelerator; };
        moderateNat = mkBoolOption { default = settings.moderateNat; };
        ipv6 = mkBoolOption { default = settings.ipv6; };
        anonymousCrashReports = mkBoolOption { default = settings.anonymousCrashReports; };
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
          inherit (config) icedos;

          inherit (icedos.applications.protonvpn-cli)
            connect
            desktopEntry
            settings
            ;

          inherit (icedosLib) validate;

          inherit (lib)
            concatStringsSep
            mkIf
            optional
            ;

          sessionTargets = icedosLib.systemd.desktopSessionTargets icedos;

          onOff = b: if b then "on" else "off";

          netshieldValue =
            if settings.netshield.full then
              "malware-ads-trackers"
            else if settings.netshield.malware then
              "malware-only"
            else
              "off";

          killSwitchValue = if settings.killSwitch then "standard" else "off";

          customDnsValid = validate.requires {
            when = settings.customDns;
            require = settings.customDnsServers != "";
            path = "icedos.applications.protonvpn-cli.settings.customDnsServers";
            msg = "must be non-empty when customDns is true";
          };

          connectArgs = concatStringsSep " " (
            optional (connect.country != "") ''--country "${connect.country}"''
            ++ optional (connect.city != "") ''--city "${connect.city}"''
            ++ optional connect.p2p "--p2p"
            ++ optional connect.securecore "-sc"
            ++ optional connect.tor "--tor"
            ++ optional connect.random "--random"
          );

          customDnsLine =
            if (customDnsValid && settings.customDns) then
              ''protonvpn config set custom-dns on --dns "${settings.customDnsServers}"''
            else
              "protonvpn config set custom-dns off";

          startScript = ''
            ${icedosLib.bash.exportSystemPath}

            flag_dir="$XDG_RUNTIME_DIR/protonvpn-cli"
            flag="$flag_dir/connected"

            # Fresh-session gate: flag lives in $XDG_RUNTIME_DIR which logind
            # wipes on full session teardown (logout / reboot). Any other
            # invocation (systemctl restart, rebuild-triggered restart) finds
            # the flag and exits early, preserving the user's runtime state.
            if [ -e "$flag" ]; then
              exit 0
            fi

            mkdir -p "$flag_dir"

            protonvpn config set netshield ${netshieldValue}
            protonvpn config set kill-switch ${killSwitchValue}
            protonvpn config set port-forwarding ${onOff settings.portForwarding}
            protonvpn config set vpn-accelerator ${onOff settings.vpnAccelerator}
            protonvpn config set moderate-nat ${onOff settings.moderateNat}
            protonvpn config set ipv6 ${onOff settings.ipv6}
            protonvpn config set anonymous-crash-reports ${onOff settings.anonymousCrashReports}
            ${customDnsLine}

            protonvpn connect ${connectArgs}

            touch "$flag"
          '';

          launcherScript = ''
            ${icedosLib.bash.exportSystemPath}

            PVPN="${pkgs.proton-vpn-cli}/bin/protonvpn"
            ZEN="${pkgs.zenity}/bin/zenity"

            action=$("$ZEN" --list --title="ProtonVPN" --column="Action" \
              Connect Disconnect Status) || exit 0

            case "$action" in
              Connect)
                country=$("$ZEN" --list --title="ProtonVPN — Country" \
                  --column="Country" \
                  Default ${concatStringsSep " " desktopEntry.countries} "Other…") || exit 0
                if [ "$country" = "Other…" ]; then
                  country=$("$ZEN" --entry --title="ProtonVPN — Country" \
                    --text="ISO country code (e.g. US, GB):") || exit 0
                fi
                if [ "$country" = "Default" ] || [ -z "$country" ]; then
                  out=$("$PVPN" connect 2>&1) || rc=$?
                else
                  out=$("$PVPN" connect --country "$country" 2>&1) || rc=$?
                fi
                if [ -n "''${rc:-}" ]; then
                  "$ZEN" --error --title="ProtonVPN" --text="$out"
                else
                  "$ZEN" --info --title="ProtonVPN" --text="$out"
                fi
                ;;
              Disconnect)
                out=$("$PVPN" disconnect 2>&1) || rc=$?
                if [ -n "''${rc:-}" ]; then
                  "$ZEN" --error --title="ProtonVPN" --text="$out"
                else
                  "$ZEN" --info --title="ProtonVPN" --text="$out"
                fi
                ;;
              Status)
                "$PVPN" status 2>&1 | "$ZEN" --text-info \
                  --title="ProtonVPN — Status" --width=520 --height=360
                ;;
            esac
          '';

          launcherBin = pkgs.writeShellScriptBin "protonvpn-launcher" launcherScript;
        in
        {
          home-manager.sharedModules = [
            {
              systemd.user.services.protonvpn-cli = {
                Unit = {
                  Description = "Proton VPN CLI";
                  After = [ "graphical-session.target" ] ++ sessionTargets;
                  PartOf = "graphical-session.target";
                  StartLimitIntervalSec = 60;
                  StartLimitBurst = 60;
                };

                Install.WantedBy = sessionTargets;

                Service = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  ExecStart = "${pkgs.writeShellScriptBin "protonvpn-cli-start" startScript}/bin/protonvpn-cli-start";
                  Nice = "-20";
                  Restart = "on-failure";
                };
              };

              xdg.desktopEntries.protonvpn = mkIf desktopEntry.enable {
                name = "ProtonVPN Controller";
                genericName = "Connect, disconnect, or check ProtonVPN status";
                icon = "protonvpn";
                exec = "${launcherBin}/bin/protonvpn-launcher";
                terminal = false;
                type = "Application";

                categories = [
                  "Network"
                  "Security"
                ];

                settings.Keywords = "vpn;proton;privacy;";
              };
            }
          ];

          environment.systemPackages = with pkgs; [
            proton-vpn-cli
            zenity
          ];
        }
      )
    ];

  meta.name = "protonvpn-cli";
}
