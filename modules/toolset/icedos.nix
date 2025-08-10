{ icedosLib, ... }:

{
  options.icedos.applications.toolset.commands =
    let
      inherit (icedosLib) mkSubmoduleListOption mkStrOption;
    in
    mkSubmoduleListOption { default = [ ]; } {
      bin = mkStrOption { };
      command = mkStrOption { };
      help = mkStrOption { };
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
          inherit (lib)
            attrNames
            concatMapStrings
            filterAttrs
            sort
            ;

          cfg = config.icedos;

          getModules =
            path:
            map (dir: ./. + ("/modules/" + dir)) (
              attrNames (filterAttrs (_: v: v == "directory") (builtins.readDir path))
            );
        in
        {
          imports = getModules (./modules);

          environment.systemPackages = [
            (
              let
                purpleString = string: ''''${PURPLE}${string}''${NC}'';
              in
              pkgs.writeShellScriptBin "icedos" ''
                PURPLE='\033[0;35m'
                NC='\033[0m'

                if [[ "$1" == "" || "$1" == "help" ]]; then
                  echo "Available commands:"

                  ${concatMapStrings (tool: ''
                    echo -e "> ${purpleString tool.command}: ${tool.help} "
                  '') (sort (a: b: a.command < b.command) (cfg.applications.toolset.commands))}

                  exit 0
                fi

                case "$1" in
                  ${concatMapStrings (tool: ''
                    ${tool.command})
                      shift
                      exec ${tool.bin} "$@"
                      ;;
                  '') cfg.applications.toolset.commands}
                  *|-*|--*)
                    echo "Unknown arg: $1" >&2
                    exit 1
                    ;;
                esac
              ''
            )
          ];
        }
      )
    ];

  meta.name = "toolset";
}
