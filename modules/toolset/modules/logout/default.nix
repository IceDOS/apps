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
      bin = "${pkgs.writeShellScript command "pkill -KILL -u $USER"}";
      command = command;
      help = "force kill all current user processes, resulting in a logout";
    }
  ];
}
