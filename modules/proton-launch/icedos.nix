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
            optionalAttrs
            splitString
            ;

          inherit (icedosLib.bash) prelude genHelpFlags purpleString;

          inherit (config.icedos) applications hardware;

          hasGamemode = config.programs.gamemode.enable;
          hasGamescope = config.programs.gamescope.enable;
          hasKde = config.services.desktopManager.plasma6.enable;
          hasPowerProfilesDaemon = config.services.power-profiles-daemon.enable;

          packages = [ proton-launch ] ++ optional hasGamescope pkgs.gamescope;

          # Heavy maintenance firing mid-game costs far more than any log spam:
          # nix GC and fstrim are multi-GB I/O storms, and logrotate plus
          # fwupd-refresh run hourly. `systemd-inhibit` cannot gate timers, so
          # reuse the lock GAME_INHIBIT already holds as an ExecCondition. A
          # failed condition skips that run cleanly and the timer retries on its
          # next interval.
          deferWhileGaming = {
            serviceConfig.ExecCondition = pkgs.writeShellScript "defer-while-proton-launch" ''
              ! ${pkgs.systemd}/bin/systemd-inhibit --list --no-pager \
                | ${pkgs.gnugrep}/bin/grep -q proton-launch
            '';
          };

          deferredServices =
            { systemd-tmpfiles-clean = deferWhileGaming; }
            // optionalAttrs config.programs.nh.clean.enable { nh-clean = deferWhileGaming; }
            // optionalAttrs config.services.fstrim.enable { fstrim = deferWhileGaming; }
            // optionalAttrs config.services.logrotate.enable { logrotate = deferWhileGaming; }
            // optionalAttrs config.services.fwupd.enable { fwupd-refresh = deferWhileGaming; };

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
              ''
                echo -e "> ${purpleString "--gamescope"}: wrap with gamescope (via scopebuddy)"
                echo -e "> ${purpleString "--gamescope-args <args>"}: pass extra args to gamescope"
              ''
            else
              "";

          conditionalLowLatencyHelp =
            if hasGamescope then
              ''
                echo -e "> ${purpleString "--low-latency"}: enable low-latency layer (AMD anti-lag)"
                echo -e "> ${purpleString "--low-latency-force-decoupled"}: low-latency layer decoupled-queue mitigation (mostly there for marvel rivals)"
                echo -e "> ${purpleString "--low-latency-reflex"}: low-latency layer in NVIDIA Reflex mode (+NVAPI) instead of anti-lag"
                echo -e "> ${purpleString "--low-latency-reflex-spoof-nvidia"}: low-latency layer in NVIDIA Reflex mode, report GPU as NVIDIA (may trip anti-cheat / break vendor-gated features)"
              ''
            else
              "";

          conditionalKdeHelp =
            if hasKde then
              ''
                echo -e "> ${purpleString "--no-baloo-suspend"}: don't suspend the KDE baloo indexer while gaming"
              ''
            else
              "";

          conditionalNoGamePerformanceHelp =
            if hasPowerProfilesDaemon then
              ''echo -e "> ${purpleString "--no-game-performance"}: don't switch to performance power profile"''
            else
              "";

          proton-launch = (
            pkgs.writeTextFile {
              name = "proton-launch";
              executable = true;
              destination = "/bin/proton-launch";
              text = ''
                #!/usr/bin/env bash
                export LD_LIBRARY_PATH="''${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}/usr/lib32:/usr/lib"

                ${prelude}

                if [[ ${genHelpFlags { }} ]]; then
                  echo "Usage: proton-launch [OPTIONS] [--] <command> [args...]"
                  echo "Available options:"
                  echo -e "> ${purpleString "--deck"}: pretend to be a Steam Deck"
                  echo -e "> ${purpleString "--debug-logs"}: enable VKD3D/DXVK/Proton warn logging into \$XDG_RUNTIME_DIR and stop silencing output (off by default)"
                  ${conditionalGamemodeHelp}
                  ${conditionalGamescopeHelp}
                  echo -e "> ${purpleString "--fps-limit <N>"}: cap framerate at N fps"
                  echo -e "> ${purpleString "--fsr4"}: enable FSR 4 frame upscaling"
                  echo -e "> ${purpleString "--fsr4-watermark"}: show FSR4/MLFG watermark overlay"
                  echo -e "> ${purpleString "--hdr"}: enable HDR output"
                  echo -e "> ${purpleString "--hidraw"}: enable hidraw device passthrough"
                  echo -e "> ${purpleString "--lod-bias <N>"}: set DXVK/D3D9 sampler LOD bias"
                  ${conditionalLowLatencyHelp}
                  echo -e "> ${purpleString "--max-frame-latency <N>"}: cap DXGI max frame latency"
                  ${conditionalKdeHelp}
                  echo -e "> ${purpleString "--no-dll-overrides"}: clear WINEDLLOVERRIDES"
                  echo -e "> ${purpleString "--no-dxr"}: disable DirectX raytracing in VKD3D"
                  echo -e "> ${purpleString "--no-esync"}: disable esync"
                  ${conditionalNoGamemodeHelp}
                  ${conditionalNoGamePerformanceHelp}
                  echo -e "> ${purpleString "--no-gpl"}: disable DXVK graphics pipeline library"
                  echo -e "> ${purpleString "--no-mangohud"}: disable mangohud overlay (when present)"
                  echo -e "> ${purpleString "--no-ntsync"}: disable ntsync"
                  echo -e "> ${purpleString "--no-proton-sdl"}: disable proton's SDL preference"
                  echo -e "> ${purpleString "--no-rebar-upload"}: disable VRAM upload via Resizable BAR"
                  echo -e "> ${purpleString "--no-shader-cache"}: disable DXVK/VKD3D on-disk shader caches (diagnostic only: trades disk writes for much worse compilation stutter)"
                  echo -e "> ${purpleString "--shader-recording"}: enable steam's fossilize layer to record pipelines to disk while playing"
                  echo -e "> ${purpleString "--no-steam-overlay"}: disable the steam overlay vulkan layer"
                  echo -e "> ${purpleString "--sdl-x11"}: force SDL to use X11 video driver"
                  echo -e "> ${purpleString "--shader-all-cores"}: use all CPU cores for DXVK shader compilation"
                  echo -e "> ${purpleString "--wayland"}: enable Proton's native Wayland backend"
                  echo -e "> ${purpleString "--wow64"}: enable Proton's 64-bit WoW translation"
                  exit 0
                fi

                BALOO_SUSPEND=1
                DEBUG_LOGS=0
                DXVK_CONFIG_OPTS=""
                DXVK_LOG_LEVEL=none
                # `none` makes dxvk skip creating the log file entirely, so no
                # `<exe>_d3d11.log` is written into the game's install dir.
                DXVK_LOG_PATH=none
                GST_DEBUG=0
                LOW_LATENCY_LAYER=0
                LOW_LATENCY_LAYER_FORCE_DECOUPLED=0
                LOW_LATENCY_LAYER_REFLEX=0
                LOW_LATENCY_LAYER_SPOOF_NVIDIA=0
                PROTON_ENABLE_HIDRAW=0
                PROTON_ENABLE_WAYLAND=0
                PROTON_FORCE_NVAPI=0
                PROTON_LOG=0
                PROTON_NO_ESYNC=0
                PROTON_PREFER_SDL=1
                PROTON_USE_WOW64=0
                SteamDeck=0
                VKD3D_CONFIG_OPTS=""
                VKD3D_DEBUG=none
                # Separate channel from VKD3D_DEBUG, and it also defaults to
                # `fixme` when unset, so silencing one without the other still
                # leaves the shader compiler spewing to stderr during the exact
                # frames where compilation stutter hurts most.
                VKD3D_SHADER_DEBUG=none
                # winemenubuilder writes .desktop files, icons and mime entries
                # into ~/.local/share every time it runs; nothing here wants it.
                ENABLE_VK_LAYER_VALVE_steam_fossilize_1=0
                WINEDLLOVERRIDES="d3d12=n,b;dbghelp=n,b;dinput8=n,b;dsound=n,b;dwrite=n,b;dxgi=n,b;version=n,b;winhttp=n,b;wininet=n,b;winmm=n,b;winemenubuilder.exe=d;$WINEDLLOVERRIDES"
                WINEFSYNC=1
                mesa_glthread=true

                RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

                ${
                  if (hasAttr "mangohud" applications) then
                    ''
                      MANGOAPP="--mangoapp"
                      MANGOHUD="${pkgs.mangohud}/bin/mangohud"
                      MANGOHUD_CONFIGFILE="$HOME/.config/MangoHud/MangoHud.conf"
                    ''
                  else
                    ""
                }

                GAME_INHIBIT="${pkgs.systemd}/bin/systemd-inhibit --why proton-launch --what idle:sleep --"

                ${
                  if hasPowerProfilesDaemon then
                    ''
                      GAME_PERFORMANCE="${pkgs.power-profiles-daemon}/bin/powerprofilesctl launch -p performance -r proton-launch-game-performance --"
                    ''
                  else
                    ""
                }

                ${
                  if hasAttr "monitors" hardware && (length hardware.monitors) != 0 then
                    let
                      monitor = head (hardware.monitors);
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
                    --debug-logs)
                      DEBUG_LOGS=1
                      VKD3D_DEBUG=warn
                      VKD3D_SHADER_DEBUG=warn
                      DXVK_LOG_LEVEL=warn
                      # Point every sink at the tmpfs runtime dir so turning
                      # logging on never itself becomes the disk I/O problem.
                      DXVK_LOG_PATH="$RUNTIME_DIR"
                      VKD3D_LOG_FILE="$RUNTIME_DIR/vkd3d.log"
                      PROTON_LOG=1
                      PROTON_LOG_DIR="$RUNTIME_DIR"
                      GST_DEBUG=2
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
                        if (hasAttr "low-latency-vulkan-layer" (hardware.drivers or { })) then
                          ''
                            --low-latency)
                              LOW_LATENCY_LAYER=1
                              shift
                              ;;
                            --low-latency-force-decoupled)
                              LOW_LATENCY_LAYER=1
                              LOW_LATENCY_LAYER_FORCE_DECOUPLED=1
                              shift
                              ;;
                            --low-latency-reflex)
                              LOW_LATENCY_LAYER=1
                              LOW_LATENCY_LAYER_REFLEX=1
                              PROTON_FORCE_NVAPI=1
                              shift
                              ;;
                            --low-latency-reflex-spoof-nvidia)
                              LOW_LATENCY_LAYER=1
                              LOW_LATENCY_LAYER_REFLEX=1
                              LOW_LATENCY_LAYER_SPOOF_NVIDIA=1
                              PROTON_FORCE_NVAPI=1
                              shift
                              ;;
                          ''
                        else
                          ""
                      }
                      ${
                        if (hasAttr "gamemode" applications) then
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
                      ${
                        if hasKde then
                          ''
                            --no-baloo-suspend)
                              BALOO_SUSPEND=0
                              shift
                              ;;
                          ''
                        else
                          ""
                      }
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
                        if hasPowerProfilesDaemon then
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
                    --no-shader-cache)
                      DXVK_SHADER_CACHE=0
                      VKD3D_SHADER_CACHE_PATH=0
                      shift
                      ;;
                    --shader-recording)
                      ENABLE_VK_LAYER_VALVE_steam_fossilize_1=1
                      shift
                      ;;
                    --no-steam-overlay)
                      DISABLE_VK_LAYER_VALVE_steam_overlay_1=1
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
                DISABLE_VK_LAYER_VALVE_steam_overlay_1 \
                DXVK_ALL_CORES \
                DXVK_CONFIG \
                DXVK_FRAME_RATE \
                DXVK_LOG_LEVEL \
                DXVK_LOG_PATH \
                DXVK_SHADER_CACHE \
                ENABLE_VK_LAYER_VALVE_steam_fossilize_1 \
                FSR4_WATERMARK \
                GST_DEBUG \
                LOW_LATENCY_LAYER \
                LOW_LATENCY_LAYER_FORCE_DECOUPLED \
                LOW_LATENCY_LAYER_REFLEX \
                LOW_LATENCY_LAYER_SPOOF_NVIDIA \
                MLFG_WATERMARK \
                PROTON_ENABLE_HDR \
                PROTON_ENABLE_HIDRAW \
                PROTON_ENABLE_WAYLAND \
                PROTON_FORCE_NVAPI \
                PROTON_FSR4_UPGRADE \
                PROTON_LOG \
                PROTON_LOG_DIR \
                PROTON_NO_ESYNC \
                PROTON_PREFER_SDL \
                PROTON_USE_NTSYNC \
                PROTON_USE_WOW64 \
                SCB_GAMESCOPE_ARGS \
                SDL_VIDEODRIVER \
                SteamDeck \
                VKD3D_CONFIG \
                VKD3D_DEBUG \
                VKD3D_LOG_FILE \
                VKD3D_SHADER_CACHE_PATH \
                VKD3D_SHADER_DEBUG \
                WINEDLLOVERRIDES \
                WINEFSYNC \
                mesa_glthread

                # Proton uses `env.setdefault("WINEDEBUG", "-all")`, so exporting
                # it unconditionally would neuter PROTON_LOG=1. Only force it
                # when we are not debugging; it still matters for native wine,
                # umu and non-Proton commands, which have no such default.
                if [ "$DEBUG_LOGS" = "0" ]; then
                  export WINEDEBUG="-all"
                fi

                [[ "$MANGOAPP" != "" && "$GAMESCOPE" != "" ]] && MANGOHUD=""

                # A crashing game or anti-cheat child otherwise dumps its whole
                # address space through systemd-coredump mid-session.
                if [ "$DEBUG_LOGS" = "0" ]; then
                  ulimit -c 0
                fi

                # Catch-all for whatever still writes to stderr: proton's python
                # wrapper, pressure-vessel, anti-cheat, gamescope, mangohud and
                # any `err:` surviving WINEDEBUG=-all. Under KDE's systemd
                # startup the game runs in an app-*.scope, so all of that lands
                # in journald and gets fsynced to disk while playing. Rebinding
                # the fds with a command-less `exec` leaves the shell (and the
                # baloo trap below) intact. Point PROTON_LAUNCH_LOG at
                # "$RUNTIME_DIR/proton-launch.log" for a readable last-run log
                # that still costs no disk I/O.
                if [ "$DEBUG_LOGS" = "0" ]; then
                  exec >"''${PROTON_LAUNCH_LOG:-/dev/null}" 2>&1
                fi

                ${
                  if hasKde then
                    ''
                      BALOOCTL="$(command -v balooctl6 2>/dev/null || command -v balooctl 2>/dev/null)"
                      if [ "$BALOO_SUSPEND" = "1" ] && [ -n "$BALOOCTL" ]; then
                        "$BALOOCTL" suspend 2>/dev/null
                        trap '"$BALOOCTL" resume 2>/dev/null' EXIT INT TERM
                      fi
                    ''
                  else
                    ""
                }

                $GAME_INHIBIT $GAME_PERFORMANCE $MANGOHUD $GAMEMODE $GAMESCOPE "''${COMMAND[@]}"
              '';
            }
          );
        in
        {
          environment.systemPackages = packages;
          systemd.services = deferredServices;

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
