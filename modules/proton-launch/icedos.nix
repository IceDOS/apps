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

          inherit (icedosLib.bash) prelude genHelpFlags purpleString;

          cfg = config.icedos;
          hasGamescope = hasAttr "gamescope" cfg.applications;
          hasGamemode = hasAttr "gamemode" cfg.applications;
          hasPowerProfilesDaemon = hasAttr "power-profiles-daemon" cfg.applications;

          packages = [ proton-launch ] ++ optional hasGamescope pkgs.gamescope;

          conditionalGamemodeHelp =
            if hasGamemode then
              ''echo -e "> ${purpleString "--gamemode"}: wrap with feral gamemoderun"''
            else
              "";

          conditionalNoGamemodeHelp =
            if hasGamemode then
              ''echo -e "> ${purpleString "--no-gamemode"}: don't wrap with gamemode"''
            else
              "";

          conditionalGamescopeHelp =
            if hasGamescope then
              ''echo -e "> ${purpleString "--gamescope"}: wrap with gamescope (via scopebuddy)"''
            else
              "";

          conditionalNoGamePerformanceHelp =
            if hasPowerProfilesDaemon then
              ''echo -e "> ${purpleString "--no-game-performance"}: don't switch to performance power profile"''
            else
              "";

          proton-launch = (
            pkgs.writeShellScriptBin "proton-launch" ''
              ${prelude}

              if [[ ${genHelpFlags { }} ]]; then
                echo "Usage: proton-launch [OPTIONS] [--] <command> [args...]"
                echo "Available options:"
                echo -e "> ${purpleString "--deck"}: pretend to be a Steam Deck"
                echo -e "> ${purpleString "--fps-limit <N>"}: cap framerate at N fps"
                echo -e "> ${purpleString "--fsr4"}: enable FSR 4 frame upscaling"
                echo -e "> ${purpleString "--fsr4-watermark"}: show FSR4/MLFG watermark overlay"
                echo -e "> ${purpleString "--gamescope-args <args>"}: pass extra args to gamescope"
                echo -e "> ${purpleString "--hdr"}: enable HDR output"
                echo -e "> ${purpleString "--hidraw"}: enable hidraw device passthrough"
                echo -e "> ${purpleString "--lod-bias <N>"}: set DXVK/D3D9 sampler LOD bias"
                echo -e "> ${purpleString "--max-frame-latency <N>"}: cap DXGI max frame latency"
                echo -e "> ${purpleString "--no-dll-overrides"}: clear WINEDLLOVERRIDES"
                echo -e "> ${purpleString "--no-dxr"}: disable DirectX raytracing in VKD3D"
                echo -e "> ${purpleString "--no-esync"}: disable esync"
                echo -e "> ${purpleString "--no-gpl"}: disable DXVK graphics pipeline library"
                echo -e "> ${purpleString "--no-mangohud"}: disable mangohud overlay (when present)"
                echo -e "> ${purpleString "--no-ntsync"}: disable ntsync"
                echo -e "> ${purpleString "--no-proton-sdl"}: disable proton's SDL preference"
                echo -e "> ${purpleString "--no-rebar-upload"}: disable VRAM upload via Resizable BAR"
                echo -e "> ${purpleString "--sdl-x11"}: force SDL to use X11 video driver"
                echo -e "> ${purpleString "--shader-all-cores"}: use all CPU cores for DXVK shader compilation"
                echo -e "> ${purpleString "--wayland"}: enable Proton's native Wayland backend"
                echo -e "> ${purpleString "--wow64"}: enable Proton's 64-bit WoW translation"
                ${conditionalGamemodeHelp}
                ${conditionalGamescopeHelp}
                ${conditionalNoGamemodeHelp}
                ${conditionalNoGamePerformanceHelp}
                exit 0
              fi

              DXVK_CONFIG_OPTS=""
              DXVK_LOG_LEVEL=warn
              PROTON_ENABLE_HIDRAW=0
              PROTON_ENABLE_WAYLAND=0
              PROTON_NO_ESYNC=0
              PROTON_PREFER_SDL=1
              PROTON_USE_WOW64=0
              SteamDeck=0
              VKD3D_CONFIG_OPTS=""
              VKD3D_DEBUG=warn
              WINEDLLOVERRIDES="d3d12=n,b;dbghelp=n,b;dinput8=n,b;dsound=n,b;dwrite=n,b;dxgi=n,b;version=n,b;winhttp=n,b;wininet=n,b;winmm=n,b;$WINEDLLOVERRIDES"
              WINEFSYNC=1
              mesa_glthread=true

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
                if (hasAttr "power-profiles-daemon" cfg.applications) then
                  ''
                    GAME_PERFORMANCE="${pkgs.systemd}/bin/systemd-inhibit --why proton-launch-game-performance ${pkgs.power-profiles-daemon}/bin/powerprofilesctl launch -p performance -r proton-launch-game-performance --"
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
                  --fsr4-watermark)
                    FSR4_WATERMARK=1
                    MLFG_WATERMARK=1
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
                  --lod-bias)
                    DXVK_CONFIG_OPTS="''${DXVK_CONFIG_OPTS:+$DXVK_CONFIG_OPTS;}d3d11.samplerLodBias = $2;d3d9.samplerLodBias = $2"
                    shift 2
                    ;;
                  --max-frame-latency)
                    DXVK_CONFIG_OPTS="''${DXVK_CONFIG_OPTS:+$DXVK_CONFIG_OPTS;}dxgi.maxFrameLatency = $2"
                    shift 2
                    ;;
                  --sdl-x11)
                    SDL_VIDEODRIVER="x11"
                    shift
                    ;;
                  --shader-all-cores)
                    DXVK_ALL_CORES=1
                    shift
                    ;;
                  --no-dll-overrides)
                    WINEDLLOVERRIDES=""
                    shift
                    ;;
                  --no-dxr)
                    VKD3D_CONFIG_OPTS="''${VKD3D_CONFIG_OPTS:+$VKD3D_CONFIG_OPTS,}nodxr"
                    shift
                    ;;
                  --no-esync)
                    PROTON_NO_ESYNC=1
                    shift
                    ;;
                  --no-gamemode)
                    GAMEMODE=""
                    shift
                    ;;
                    ${
                      if (hasAttr "power-profiles-daemon" cfg.applications) then
                        ''
                          --no-game-performance)
                            GAME_PERFORMANCE=""
                            shift
                            ;;
                        ''
                      else
                        ""
                    }
                  --no-gpl)
                    DXVK_CONFIG_OPTS="''${DXVK_CONFIG_OPTS:+$DXVK_CONFIG_OPTS;}dxvk.enableGraphicsPipelineLibrary = False"
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
                  --no-rebar-upload)
                    VKD3D_CONFIG_OPTS="''${VKD3D_CONFIG_OPTS:+$VKD3D_CONFIG_OPTS,}no_upload_hvv"
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

              [ -n "$DXVK_CONFIG_OPTS" ] && DXVK_CONFIG="$DXVK_CONFIG_OPTS"
              [ -n "$VKD3D_CONFIG_OPTS" ] && VKD3D_CONFIG="$VKD3D_CONFIG_OPTS"

              export \
              DXVK_ALL_CORES \
              DXVK_CONFIG \
              DXVK_FRAME_RATE \
              DXVK_LOG_LEVEL \
              FSR4_WATERMARK \
              MLFG_WATERMARK \
              PROTON_ENABLE_HDR \
              PROTON_ENABLE_HIDRAW \
              PROTON_ENABLE_WAYLAND \
              PROTON_FSR4_UPGRADE \
              PROTON_NO_ESYNC \
              PROTON_PREFER_SDL \
              PROTON_USE_NTSYNC \
              PROTON_USE_WOW64 \
              SCB_GAMESCOPE_ARGS \
              SDL_VIDEODRIVER \
              SteamDeck \
              VKD3D_CONFIG \
              VKD3D_DEBUG \
              WINEDLLOVERRIDES \
              WINEFSYNC \
              mesa_glthread

              [[ "$MANGOAPP" != "" && "$GAMESCOPE" != "" ]] && MANGOHUD=""

              $GAME_PERFORMANCE $MANGOHUD $GAMEMODE $GAMESCOPE "''${COMMAND[@]}"
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
