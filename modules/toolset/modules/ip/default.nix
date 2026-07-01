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
      script = "(${curl} ipinfo.io/$(${curl} ifconfig.me)) 2>/dev/null | ${pkgs.jq}/bin/jq";
      help = "print current ip info";
    }
  ];
}
