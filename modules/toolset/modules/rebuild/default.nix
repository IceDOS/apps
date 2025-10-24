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
        CACHE_DIR=".cache"

        LATEST_FOLDER=$(ls -dt "$CACHE_DIR"/*/ 2>/dev/null | head -1)

        if [ -n "$LATEST_FOLDER" ]; then
          CACHED_FILE=$(find "$LATEST_FOLDER" -name "$FILE" | head -1)

          if [ -f "$CACHED_FILE" ]; then
            if diff -q "$FILE" "$CACHED_FILE" &> /dev/null; then
              IS_CACHED=1
            fi
          fi
        fi

        if [[ ! "$IS_CACHED" -eq 1 ]]; then
          DATE_FOLDER="$CACHE_DIR/$(date -Is)"
          mkdir -p "$DATE_FOLDER"
          cp "$FILE" "$DATE_FOLDER"
        fi
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
        nix-shell ./build.sh --update $@
      else
        nix-shell ./build.sh $@
      fi

      cache "config.toml"
      cache "flake.lock"
      cache "flake.nix"
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
