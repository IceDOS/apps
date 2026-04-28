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
        if [[ "$1" == "--torrent" ]]; then
          if [[ "$2" == "" ]]; then
            log_info "usage: icedos download --torrent [URI | MAGNET | TORRENT_FILE] [DOWNLOAD_DIR]"
            die "specify torrent url/magnet/file as an argument"
          fi

          "${pkgs.transmission_4}/bin/transmission-cli" -B -D -ep -U -w "''${3:-.}" "$2"
          exit $?
        fi

        if [[ ${genHelpFlags { }} ]]; then
          log_info "usage: icedos download [OPTIONS] [URI | MAGNET | TORRENT_FILE | METALINK_FILE]..."
          log_info "       icedos download --torrent [URI | MAGNET | TORRENT_FILE] [DOWNLOAD_DIR]"
          die "specify url as an argument"
        fi

        "${pkgs.aria2}/bin/aria2c" -j 16 -s 16 "$@"
      '';

      help = "download provided url using aria2c or transmission, aiming max speed";
    }
  ];
}
