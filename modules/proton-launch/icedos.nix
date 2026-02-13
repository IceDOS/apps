{ icedosLib, ... }:

{
  inputs.scopebuddy = {
    url = "github:HikariKnight/ScopeBuddy";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  options.icedos.applications.proton-launch = icedosLib.mkBoolOption { default = true; };

  outputs.nixosModules =
    { inputs, ... }:
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
              SteamDeck=0

              WINEDLLOVERRIDES="d3d12=n,b;dbghelp=n,b;dinput8=n,b;dsound=n,b;dwrite=n,b;dxgi=n,b;version=n,b;winhttp=n,b;wininet=n,b;winmm=n,b;$WINEDLLOVERRIDES"

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
                  --sdl-x11)
                    SDL_VIDEODRIVER="x11"
                    shift
                    ;;
                  --no-dll-overrides)
                    WINEDLLOVERRIDES=""
                    shift
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
                  --no-ntsync)
                    PROTON_USE_NTSYNC=0
                    shift
                    ;;
                  --no-proton-sdl)
                    PROTON_PREFER_SDL=0
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

              SCB_GAMESCOPE_ARGS="$DEFAULT_HEIGHT $DEFAULT_REFRESH_RATE $DEFAULT_WIDTH $GAMESCOPE_ARGS $MANGOAPP"

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
              SDL_VIDEODRIVER \
              SteamDeck \
              WINEDLLOVERRIDES

              [[ "$MANGOAPP" != "" && "$GAMESCOPE" != "" ]] && MANGOHUD=""

              $MANGOHUD $GAMEMODE $GAMESCOPE "''${COMMAND[@]}"
            ''
          );
        in
        {
          environment.systemPackages = packages;

          nixpkgs.overlays = [
            (final: super: {
              inherit proton-launch;
              scopebuddy = inputs.scopebuddy.packages.${pkgs.stdenv.system}.default;
            })
          ];
        }
      )
    ];

  meta.name = "proton-launch";
}
