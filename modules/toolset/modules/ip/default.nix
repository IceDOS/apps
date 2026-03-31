{
  pkgs,
  ...
}:

let
  command = "ip";
  curl = "${pkgs.curl}/bin/curl";
in
{
  icedos.applications.toolset.commands = [
    {
      inherit command;
      bin = "${pkgs.writeShellScript command "(${curl} ipinfo.io/$(${curl} ifconfig.me)) 2>/dev/null | ${pkgs.jq}/bin/jq"}";
      help = "print current ip info";
    }
  ];
}
