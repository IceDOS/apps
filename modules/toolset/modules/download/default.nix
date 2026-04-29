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
      command = "download";

      script = ''
        if [[ ${genHelpFlags { }} ]]; then
          log_info "usage: icedos download [OPTIONS] [URI | MAGNET | TORRENT_FILE | METALINK_FILE]..."
          die "specify url as an argument"
        fi

        "${pkgs.aria2}/bin/aria2c" -j 16 -s 16 --seed-time=0 "$@"
      '';

      help = "download URLs, torrents, or magnets via aria2c at max speed";

      completion.files = true;
    }
  ];
}
