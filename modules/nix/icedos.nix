{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          inputs,
          lib,
          pkgs,
          ...
        }:

        let
          inherit (lib) mapAttrs mapAttrsToList;
        in
        {
          icedos.applications.toolset.commands = [
            (
              let
                inherit (lib) concatMapStrings sort;

                colorBashHeader = ''
                  NC='\033[0m'
                  PURPLE='\033[0;35m'
                  RED='\033[0;31m'
                '';

                helpFlags = ''"$1" == "" || "$1" == "--help" || "$1" == "-h" || "$1" == "help" || "$1" == "h"'';

                commands = [
                  (
                    let
                      command = "list";
                    in
                    {
                      bin = "${pkgs.writeShellScript command "nix-store --query --requisites /run/current-system | cut -d- -f2- | sort | uniq"}";
                      command = command;
                      help = "list installed packages";
                    }
                  )
                  (
                    let
                      command = "build";
                    in
                    {
                      bin = "${pkgs.writeShellScript command ''
                        ${colorBashHeader}

                        if [[ ${helpFlags} ]]; then
                          echo "Available arguments:"
                          echo -e "> ${purpleString "--run|-r"}: provide binary name to launch after building"
                          echo -e "> ${purpleString "--path|-p"}: provide nix derivation path to build"
                          exit 0
                        fi

                        while [[ $# -gt 0 ]]; do
                          case "$1" in
                            --path|-p)
                              BUILD="nix-build -E '(import <nixpkgs> {}).callPackage $2 {}'"
                              shift 2
                              ;;
                            --run|-r)
                              RUN="| xargs -I {} bash -c '{}/bin/$2'"
                              shift 2
                              ;;
                            *)
                              echo -e "${redString "Unknown arg"}: $1"
                              exit 1
                          esac
                        done

                        [ "$BUILD" == "" ] && echo -e "${redString "error"}: --path|-p is required" && exit 1

                        bash -c "$BUILD $RUN"
                      ''}";

                      command = command;
                      help = "build provided package derivation";
                    }
                  )
                ];

                command = "pkgs";
                purpleString = string: ''''${PURPLE}${string}''${NC}'';
                redString = string: ''''${RED}${string}''${NC}'';
              in
              {
                bin = "${pkgs.writeShellScript command ''
                  ${colorBashHeader}

                  if [[ ${helpFlags} ]]; then
                    echo "Available commands:"

                    ${concatMapStrings (tool: ''
                      echo -e "> ${purpleString tool.command}: ${tool.help} "
                    '') (sort (a: b: a.command < b.command) commands)}

                    exit 0
                  fi

                  case "$1" in
                    ${concatMapStrings (tool: ''
                      ${tool.command})
                        shift
                        exec ${tool.bin} "$@"
                        ;;
                    '') commands}
                    *|-*|--*)
                      echo -e "${redString "Unknown arg"}: $1" >&2
                      exit 1
                      ;;
                  esac
                ''}";

                command = command;
                help = "print package related commands";
              }
            )

            (
              let
                command = "repair";
              in
              {
                bin = "${pkgs.writeShellScript command "nix-store --verify --check-contents --repair"}";
                command = command;
                help = "repair nix store";
              }
            )
          ];

          nix = {
            # Use flake's nixpkgs input for nix-shell
            nixPath = mapAttrsToList (key: _: "${key}=flake:${key}") config.nix.registry;
            registry = mapAttrs (_: v: { flake = v; }) inputs;

            settings = {
              auto-optimise-store = true;

              experimental-features = [
                "nix-command"
                "flakes"
              ];
            };
          };

          nixpkgs.config.allowUnfree = true;
        }
      )
    ];

  meta.name = "nix";
}
