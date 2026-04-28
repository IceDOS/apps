{
  icedosLib,
  pkgs,
  ...
}:

let
  inherit (icedosLib.bash) genHelpFlags;
in
{
  icedos.applications.toolset.commands = [
    {
      command = "btrfs-zstd";

      script = ''
        if [[ ${genHelpFlags { }} ]]; then
          die "specify path as an argument"
        fi

        sudo "${pkgs.btrfs-progs}/bin/btrfs" filesystem defrag -czstd -r -v "$@"
      '';

      help = "compress btrfs path using zstd";
    }
  ];
}
