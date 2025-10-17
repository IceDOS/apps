{ icedosLib, ... }:

{
  options.icedos.applications.proton-launch = icedosLib.mkBoolOption { default = true; };

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
            hasAttr
            head
            last
            length
            mapAttrs
            mkIf
            optional
            splitString
            ;

          cfg = config.icedos;
          hasGamescope = hasAttr "gamescope" cfg.applications;

          packages = [ proton-launch ] ++ optional hasGamescope pkgs.gamescope;

          proton-launch = (
            pkgs.writeShellScriptBin "proton-launch" ''
              PROTON_ENABLE_HIDRAW=0
              PROTON_ENABLE_WAYLAND=0
              PROTON_PREFER_SDL=1
              PROTON_USE_WOW64=0
              SDL="--backend sdl"
              SteamDeck=0

              ${
                if (hasAttr "mangohud" cfg.applications) then
                  ''
                    MANGOAPP="--mangoapp"
                    MANGOHUD="${pkgs.mangohud}/bin/mangohud"
                    MANGOHUD_CONFIGFILE="/home/$USER/.config/MangoHud/MangoHud.conf"
                  ''
                else
                  ""
              }

              ${
                if hasAttr "monitors" cfg.hardware && (length cfg.hardware.monitors) != 0 then
                  let
                    monitor = head (cfg.hardware.monitors);
                    resolution = splitString "x" (monitor.resolution);
                    width = head resolution;
                    height = last resolution;
                    refreshRate = toString (monitor.refreshRate);
                  in
                  ''
                    DEFAULT_WIDTH="-W ${width}"
                    DEFAULT_HEIGHT="-H ${height}"
                    DEFAULT_REFRESH_RATE="-r ${refreshRate}"
                  ''
                else
                  ""
              }

              while [[ $# -gt 0 ]]; do
                case "$1" in
                  --deck)
                    SteamDeck=1
                    shift
                    ;;
                  --fps-limit)
                    DXVK_FRAME_RATE="$2"
                    shift 2
                    ;;
                  --fsr4)
                    PROTON_FSR4_UPGRADE=1
                    shift
                    ;;
                  --hdr)
                    PROTON_ENABLE_HDR=1
                    shift
                    ;;
                  --hidraw)
                    PROTON_ENABLE_HIDRAW=1
                    shift
                    ;;
                    ${
                      if (hasAttr "gamemode" cfg.applications) then
                        ''
                          --gamemode)
                            GAMEMODE="${pkgs.gamemode}/bin/gamemoderun"
                            shift
                            ;;
                        ''
                      else
                        ""
                    }
                    ${
                      if hasGamescope then
                        ''
                          --gamescope)
                            GAMESCOPE="${pkgs.scopebuddy}/bin/scopebuddy --"
                            shift
                            ;;
                        ''
                      else
                        ""
                    }
                  --gamescope-args)
                    GAMESCOPE_ARGS="$2"

                    if [[ $GAMESCOPE_ARGS = *'-W'* ]] || [[ $GAMESCOPE_ARGS = *'-H'* ]]; then
                      DEFAULT_WIDTH=""
                      DEFAULT_HEIGHT=""
                    fi

                    if [[ $GAMESCOPE_ARGS = *'-r'* ]]; then
                      DEFAULT_REFRESH_RATE=""
                    fi

                    shift 2
                    ;;
                  --no-gamemode)
                    GAMEMODE=""
                    shift
                    ;;
                  --no-mangohud)
                    MANGOHUD=""
                    MANGOAPP=""
                    shift
                    ;;
                  --no-sdl)
                    SDL=""
                    PROTON_PREFER_SDL=0
                    shift
                    ;;
                  --no-ntsync)
                    PROTON_USE_NTSYNC=0
                    shift
                    ;;
                  --wayland)
                    PROTON_ENABLE_WAYLAND=1
                    shift
                    ;;
                  --wow64)
                    PROTON_USE_WOW64=1
                    shift
                    ;;
                  --)
                    shift
                    COMMAND=("$@")
                    break
                    ;;
                  *)
                    COMMAND=("$@")
                    break
                    ;;
                  -*|--*)
                    echo "Unknown arg: $1" >&2
                    exit 1
                    ;;
                esac
              done

              SCB_GAMESCOPE_ARGS="$DEFAULT_HEIGHT $DEFAULT_REFRESH_RATE $DEFAULT_WIDTH $GAMESCOPE_ARGS $MANGOAPP $SDL"

              export \
              DXVK_FRAME_RATE \
              PROTON_ENABLE_HDR \
              PROTON_ENABLE_HIDRAW \
              PROTON_ENABLE_WAYLAND \
              PROTON_FSR4_UPGRADE \
              PROTON_PREFER_SDL \
              PROTON_USE_NTSYNC \
              PROTON_USE_WOW64 \
              SCB_GAMESCOPE_ARGS \
              SteamDeck

              [[ "$MANGOAPP" != "" && "$GAMESCOPE" != "" ]] && MANGOHUD=""

              $MANGOHUD $GAMEMODE $GAMESCOPE "''${COMMAND[@]}"
            ''
          );

          ifSteam = deck: lib.hasAttr "steam" cfg.applications && deck;
          steamdeck = hasAttr "steamdeck" cfg.hardware.devices;
        in
        {
          environment.systemPackages = packages;

          icedos.applications.toolset.commands = [
            (
              let
                command = "proton-launch";
              in
              {
                bin = "${proton-launch}/bin/${command}";
                command = command;
                help = "launch exec using optimal usage flags for gaming";
              }
            )
          ];

          programs.steam.extraPackages = mkIf (ifSteam steamdeck) packages;

          nixpkgs.overlays = [
            (final: super: {
              scopebuddy = final.callPackage ./lib/scopebuddy.nix { };
            })
          ];

          home-manager.users = mapAttrs (user: _: {
            home.packages = mkIf (ifSteam (!steamdeck)) [
              (pkgs.steam.override { extraPkgs = pkgs: packages; })
            ];
          }) cfg.users;
        }
      )
    ];

  meta.name = "proton-launch";
}
