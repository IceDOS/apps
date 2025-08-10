{ icedosLib, ... }:

{
  options.icedos.applications.wg-quick.interfaces = icedosLib.mkStrListOption { default = [ ]; };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:

        let
          inherit (lib) listToAttrs;
          interfaces = config.icedos.applications.wg-quick.interfaces;
        in
        {
          networking.wg-quick.interfaces = listToAttrs (
            map (name: {
              inherit name;

              value = {
                configFile = "/etc/wireguard/${name}.conf";
              };
            }) interfaces
          );

          icedos.internals.toolset.commands = [
            (
              let
                command = "wg-config";
              in
              {
                bin = "${pkgs.writeShellScript command ''
                  sudo bash -c '
                    set -e

                    if [[ "$1" == "" ]]; then
                      echo "error: provide config file location as an argument"
                      exit 1
                    fi

                    newFile="/etc/wireguard/''$(basename $1)"

                    mkdir -p /etc/wireguard
                    umask 0022 /etc/wireguard

                    cp "$1" "$newFile"
                    chmod 600 "$newFile"
                    rm "$1"
                  ' -- $@
                ''}";
                command = command;
                help = "add wireguard config to /etc/wireguard";
              }
            )
          ];
        }
      )
    ];

  meta.name = "wg-quick";
}
