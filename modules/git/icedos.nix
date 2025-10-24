{ lib, icedosLib, ... }:

{
  options.icedos.applications.git.users =
    let
      inherit (icedosLib) mkStrOption mkSubmoduleAttrsOption;

      defaultConfig =
        let
          inherit (lib) fromTOML readFile;
        in
        (fromTOML (readFile ./config.toml)).icedos.applications.git.users.username;
    in
    mkSubmoduleAttrsOption { default = { }; } {
      username = mkStrOption { default = defaultConfig.username; };
      email = mkStrOption { default = defaultConfig.email; };
    };

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
          inherit (lib) mapAttrs;
          cfg = config.icedos;
          users = cfg.applications.git.users;
        in
        {
          home-manager.users = mapAttrs (user: _: {
            home.packages = [ pkgs.lazygit ];

            programs.git = {
              enable = true;

              settings = {
                user.email = "${users.${user}.username}";
                user.name = "${users.${user}.email}";
              };
            };
          }) cfg.users;

          icedos.applications.toolset.commands = [
            (
              let
                command = "extract-commit";
              in
              {
                inherit command;

                bin = "${pkgs.writeShellScript command ''
                  GREEN='\e[32m'
                  PURPLE='\e[35m'
                  RED='\e[31m'
                  YELLOW='\e[33m'
                  NO_COLOR='\e[0m'

                  function coloredString() {
                    echo -e "$1$2$NO_COLOR"
                  }

                  COMMIT_ARG_COLORED=$(coloredString $YELLOW "-c|--commit")
                  DESTINATION_ARG_COLORED=$(coloredString $YELLOW "-d|--destination")

                  function printHelp() {
                    echo "Available arguments:"
                    echo -e "> $COMMIT_ARG_COLORED: commit hash from which a file list will be generated"
                    echo -e "> $DESTINATION_ARG_COLORED: path to copy generated file list to"
                    echo -e "> $(coloredString $PURPLE "--fetch-files-from-commit"): fetch files content from commit, instead of current tree"
                    echo -e "\n($(coloredString $GREEN !)) Yellow-colored arguments are required"
                  }

                  if [[ $# -le 1 ]]; then
                    printHelp
                    exit 0
                  fi

                  while [[ $# -gt 0 ]]; do
                    case "$1" in
                      -c|--commit)
                        COMMIT="$2"
                        shift 2
                        ;;
                      -d|--destination)
                        DESTINATION="$2"
                        shift 2
                        ;;
                      --fetch-files-from-commit)
                        FETCH_COMMIT=1
                        shift
                        ;;
                      *)
                        echo -e "$(coloredString $RED "error"): uknown arg \"$1\" \n"
                        printHelp
                        exit 1
                    esac
                  done

                  ERROR_COLORED=$(coloredString $RED error)

                  [ "$COMMIT" == "" ] && echo -e "$ERROR_COLORED: $COMMIT_ARG_COLORED required" && exit 1
                  [ "$DESTINATION" == "" ] && echo -e "$ERROR_COLORED: $DESTINATION_ARG_COLORED required" && exit 1

                  FILES_TO_EXTRACT=$(git diff-tree --no-commit-id --name-only -r "$COMMIT" 2>/dev/null)

                  [ -z "''${FILES_TO_EXTRACT[@]}" ] && echo -e "$ERROR_COLORED: no files to extract, make sure the commit hash is correct and not empty" && exit 1

                  mkdir -p "$DESTINATION"

                  for file in $FILES_TO_EXTRACT; do
                    source_dir=$(dirname "$file")
                    dest_dir="$DESTINATION/$source_dir"

                    mkdir -p "$dest_dir"

                    case $FETCH_COMMIT in
                      1)
                        git show "''${COMMIT}:''${file}" > "$DESTINATION/$file"
                        ;;
                      *)
                        if [[ ! -e "$file" ]]; then
                          echo -e "$ERROR_COLORED: failed to copy \"$file\", file is not present in current structure"
                          continue
                        fi

                        cp "$file" "$DESTINATION/$file"
                        ;;
                    esac
                  done
                ''}";

                help = ''-c <commit_hash> -d <destination_directory>'';
              }
            )
          ];
        }
      )
    ];

  meta.name = "git";
}
