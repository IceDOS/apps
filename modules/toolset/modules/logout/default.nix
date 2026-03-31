{
  pkgs,
  ...
}:

let
  command = "logout";
in
{
  icedos.applications.toolset.commands = [
    {
      inherit command;
      bin = "${pkgs.writeShellScript command "pkill -KILL -u $USER"}";
      help = "force kill all current user processes, resulting in a logout";
    }
  ];
}
