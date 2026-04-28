{ icedosLib, lib, ... }:

{
  options.icedos.applications.wg-quick.interfaces =
    let
      inherit (lib) readFile;
      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.wg-quick) interfaces;
    in
    icedosLib.mkStrListOption { default = interfaces; };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          ...
        }:

        let
          inherit (lib) listToAttrs;
          inherit (icedosLib.bash) genHelpFlags;
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

          icedos.applications.toolset.commands = [
            {
              command = "wg-config";

              script = ''
                if [[ ${genHelpFlags { }} ]]; then
                  die "provide config file location as an argument"
                fi

                sudo bash -c '
                  set -e

                  newFile="/etc/wireguard/''$(basename "$1")"

                  mkdir -p /etc/wireguard
                  umask 0022 /etc/wireguard

                  cp "$1" "$newFile"
                  chmod 600 "$newFile"
                  rm "$1"
                ' -- "$@"
              '';

              help = "add wireguard config to /etc/wireguard";
            }
          ];
        }
      )
    ];

  meta.name = "wg-quick";
}
