{
  pkgs,
  ...
}:

let
  curl = "${pkgs.curl}/bin/curl";
in
{
  icedos.system.toolset.commands = [
    {
      command = "ip";
      script = ''
        # Ask ipinfo.io about the caller directly. Putting the public IP in the
        # request path (ipinfo.io/$IP) leaks it into the URL, so never
        # interpolate it — one call, no IP in the query. /json makes the
        # content-negotiation explicit instead of relying on the curl UA.
        RESP="$(${curl} -sf "https://ipinfo.io/json" 2>/dev/null || true)"
        if [ -n "$RESP" ]; then
          printf '%s\n' "$RESP" | ${pkgs.jq}/bin/jq
        else
          die "ip: could not determine public IP"
        fi
      '';
      help = "print current ip info";
    }
  ];
}
