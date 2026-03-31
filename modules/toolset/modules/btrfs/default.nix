{
  pkgs,
  ...
}:

{
  icedos.applications.toolset.commands = [
    (
      let
        command = "btrfs-zstd";
      in
      {
        inherit command;

        bin = "${pkgs.writeShellScript command ''
          if [[ "$1" == "" ]]; then
            echo "error: specify path as an argument"
            exit 1
          fi

          sudo "${pkgs.btrfs-progs}/bin/btrfs" filesystem defrag -czstd -r -v "$@"
        ''}";

        help = "compress btrfs path using zstd";
      }
    )
  ];
}
