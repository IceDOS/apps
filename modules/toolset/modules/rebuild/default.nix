{
  config,
  pkgs,
  ...
}:

let
  builder =
    c: u:
    let
      inherit (pkgs) flatpak writeShellScript;
      flatpakUpdate = if (config.services.flatpak.enable) then "${flatpak}/bin/flatpak update" else "";
    in
    "${writeShellScript "${c}" ''
      RED='\033[0;31m'
      NC='\033[0m'

      function cache() {
        FILE="$1"

        [ ! -f "$FILE" ] && return 1
        mkdir -p .cache

        LASTFILE=$(ls -lt ".cache" | grep "$FILE" | head -2 | tail -1 | awk '{print $9}')

        diff -sq ".cache/$LASTFILE" "$FILE" &> /dev/null || cp "$FILE" ".cache/$FILE-$(date -Is)"
      }

      function runCommand() {
        if command -v "$1" &> /dev/null
        then
          "$1"
        fi
      }

      cd ${config.icedos.configurationLocation} 2> /dev/null ||
      (echo -e "''${RED}error''${NC}: configuration path is invalid, run build.sh located inside the configuration scripts directory to update the path." && false) &&

      if ${u}; then
        ${flatpakUpdate}

        nix-shell ./build.sh --update $@ &&

        cache "flake.lock"
        cache "flake.nix"
      else
        nix-shell ./build.sh $@
      fi
    ''}";
in
{
  icedos.applications.toolset.commands = [
    (
      let
        command = "rebuild";
      in
      {
        bin = toString (builder command "false");
        command = command;
        help = "rebuild the system";
      }
    )

    (
      let
        command = "update";
      in
      {
        bin = toString (builder command "true");
        command = command;
        help = "update flake.lock and rebuild the system";
      }
    )
  ];
}
