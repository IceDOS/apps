{
  pkgs,
  ...
}:

{
  icedos.applications.toolset.commands = [
    {
      command = "btrfs-zstd";

      script = ''
        if [[ "$1" == "" ]]; then
          echo "error: specify path as an argument"
          exit 1
        fi

        sudo "${pkgs.btrfs-progs}/bin/btrfs" filesystem defrag -czstd -r -v "$@"
      '';

      help = "compress btrfs path using zstd";
    }
  ];
}
