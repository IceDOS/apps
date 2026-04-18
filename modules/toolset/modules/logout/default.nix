{ ... }:

{
  icedos.applications.toolset.commands = [
    {
      command = "logout";
      script = "pkill -KILL -u $USER";
      help = "force kill all current user processes, resulting in a logout";
    }
  ];
}
