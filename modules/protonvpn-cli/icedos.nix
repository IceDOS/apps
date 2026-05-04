{ icedosLib, lib, ... }:

{
  options.icedos.applications.protonvpn-cli =
    let
      inherit (icedosLib) mkBoolOption mkStrOption;
      inherit (lib) readFile;
      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.protonvpn-cli)
        connect
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
          cfg = config.icedos;

          inherit (cfg.applications.protonvpn-cli) connect settings;
          inherit (icedosLib) abortIf;
          inherit (lib) concatStringsSep optional;

          sessionTargets = icedosLib.systemd.desktopSessionTargets cfg;

          onOff = b: if b then "on" else "off";

          netshieldValue =
            if settings.netshield.full then
              "malware-ads-trackers"
            else if settings.netshield.malware then
              "malware-only"
            else
              "off";

          killSwitchValue = if settings.killSwitch then "standard" else "off";

          customDnsValid =
            abortIf (settings.customDns && settings.customDnsServers == "")
              "icedos.applications.protonvpn-cli.settings.customDnsServers must be non-empty when customDns is true.";

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
            }
          ];

          environment.systemPackages = [ pkgs.proton-vpn-cli ];
        }
      )
    ];

  meta.name = "protonvpn-cli";
}
