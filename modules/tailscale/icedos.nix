{ icedosLib, lib, ... }:

{
  options.icedos.applications.tailscale.enableTrayscale =
    let
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.applications.tailscale)
        enableTrayscale
        ;
    in
    icedosLib.mkBoolOption { default = enableTrayscale; };

  outputs.nixosModules =
    { repoUrl, ... }:
    [
      (
        {
          config,
          icedosLib,
          lib,
          pkgs,
          ...
        }:

        let
          inherit (lib) mkIf optional;
          inherit (config.icedos.applications.tailscale)
            enableTrayscale
            ;

          # Only arm the split-tunnel while ProtonVPN's kill-switch is in play; without it
          # the physical default route is already used, so the rules are pointless overhead.
          hasProtonVpn = icedosLib.hasModule {
            inherit config repoUrl;
            name = "protonvpn-cli";
          };

          # ProtonVPN's kill-switch client hijacks the default route, and its WireGuard
          # tunnel is hostile to Tailscale's own UDP/DERP (UDP probed blocked, DERP-over-TLS
          # times out). Split Tailscale's control-plane + DERP traffic onto the physical NIC.
          splitScript = pkgs.writeShellApplication {
            name = "icedos-tailscale-split-tunnel";

            runtimeInputs = [
              pkgs.coreutils # sort
              pkgs.gawk # awk
              pkgs.iproute2 # ip
              pkgs.tailscale # tailscale debug derp-map
            ];

            text = ''
              set -euo pipefail
              table=2020
              # Pref must precede Tailscale's own fwmark-policy block (5210+) so its
              # marked control/DERP traffic hits this table, not main (=ProtonVPN).
              pref=5000

              # Drop stale split rules/table so each run arms a clean set.
              drain_rules() {
                n=1024
                while [ "$n" -gt 0 ] && ip rule del pref "$pref" lookup "$table" 2>/dev/null; do n=$((n-1)); done
              }
              # Clear any leftover rules from the previously-shipped preference (runs every invocation).
              migrate_legacy() {
                m=1024
                while [ "$m" -gt 0 ] && ip rule del pref 20000 lookup "$table" 2>/dev/null; do m=$((m-1)); done
              }
              migrate_legacy
              # Full teardown, used only for --stop and when no physical route exists.
              drain() {
                drain_rules
                ip route flush table "$table" 2>/dev/null || true
              }

              stop=0
              for a in "$@"; do
                if [ "$a" = "--stop" ]; then stop=1; fi
              done
              if [ "$stop" -eq 1 ]; then
                drain
                exit 0
              fi

              # Pick the physical default route, skipping any kill-switch/WG tunnels.
              phys_line="$(ip -4 route show default |
                awk '/dev (proton|pvpnksintrf|tailscale|wg)/{next} /via /{print; exit}')"
              gw=""
              dev=""
              if [ -n "$phys_line" ]; then
                gw="$(printf '%s\n' "$phys_line" | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')"
                dev="$(printf '%s\n' "$phys_line" | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
              fi
              if [ -z "$gw" ] || [ -z "$dev" ]; then
                # No physical default route yet; leave a clean slate until the next timer fire.
                drain
                exit 0
              fi

              # Keep the split table's default current so gateway changes propagate.
              ip -4 route replace default via "$gw" dev "$dev" onlink table "$table" || true

              # Targets: control-plane anycast + current DERP relay IPs.
              derp_list="$(tailscale debug derp-map 2>/dev/null |
                awk 'match($0, /"[0-9]{1,3}(\.[0-9]{1,3}){3}"/) { print substr($0, RSTART + 1, RLENGTH - 2) "/32" }' || true)"
              if [ -z "$derp_list" ]; then
                # derp-map unavailable (tailscaled mid-restart); keep the armed set as-is.
                exit 0
              fi
              desired="$( { echo "192.200.0.0/24"; printf '%s\n' "$derp_list"; } | sort -u )"

              # Skip re-arm when the armed set already matches; avoids netlink churn
              # tailscaled's monitor reacts to and a gap where marked traffic is unreachable.
              # NB: ip rule show omits the /32 for host routes, so canonicalize before compare.
              current="$(ip -4 rule show pref "$pref" 2>/dev/null |
                awk '{ for (i = 1; i <= NF; i++) if ($i == "to") { t = $(i + 1); if (t !~ /\//) t = t "/32"; print t } }' |
                sort -u)"

              if [ "$current" != "$desired" ]; then
                drain_rules
                printf '%s\n' "$desired" | while IFS= read -r cidr; do
                  ip rule add pref "$pref" lookup "$table" to "$cidr" 2>/dev/null || true
                done
              fi'';
          };
        in
        {
          environment.systemPackages = with pkgs; [ tailscale ] ++ optional enableTrayscale trayscale;
          services.tailscale.enable = true;

          systemd.services.icedos-tailscale-split-tunnel = mkIf hasProtonVpn {
            description = "Split Tailscale control/DERP traffic around the ProtonVPN tunnel";
            wantedBy = [ "multi-user.target" ];
            wants = [ "network-online.target" ];
            after = [
              "network-online.target"
              "tailscaled.service"
            ];

            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${splitScript}/bin/icedos-tailscale-split-tunnel";
            };
          };

          systemd.timers.icedos-tailscale-split-tunnel = mkIf hasProtonVpn {
            description = "Keep Tailscale split-tunnel routes in sync with its DERP map";
            wantedBy = [ "timers.target" ];

            timerConfig = {
              OnBootSec = "1min";
              OnUnitActiveSec = "5min";
              RandomizedDelaySec = "1min";
            };
          };
        }
      )
    ];

  meta.name = "tailscale";
}
