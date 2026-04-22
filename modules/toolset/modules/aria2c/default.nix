{
  pkgs,
  ...
}:

{
  icedos.applications.toolset.commands = [
    {
      command = "download";

      script = ''
        if [[ "$1" == "--torrent" ]]; then
          if [[ "$2" == "" ]]; then
            echo "error: specify torrent url/magnet/file as an argument"
            echo "usage: icedos download --torrent [URI | MAGNET | TORRENT_FILE] [DOWNLOAD_DIR]"
            exit 1
          fi

          "${pkgs.transmission_4}/bin/transmission-cli" -B -D -ep -U -w "''${3:-.}" "$2"
          exit $?
        fi

        if [[ "$1" == "" ]]; then
          echo "error: specify url as an argument"
          echo "usage: icedos download [OPTIONS] [URI | MAGNET | TORRENT_FILE | METALINK_FILE]..."
          echo "help: icedos download -h"
          exit 1
        fi

        "${pkgs.aria2}/bin/aria2c" -j 16 -s 16 "$@"
      '';

      help = "download provided url using aria2c or transmission, aiming max speed";
    }
  ];
}
