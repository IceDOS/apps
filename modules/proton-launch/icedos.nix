{ icedosLib, lib, ... }:

{
  inputs.scopebuddy = {
    url = "github:HikariKnight/ScopeBuddy";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  options.icedos.applications.proton-launch =
    let
      inherit (lib) importTOML;
      inherit ((importTOML ./config.toml).icedos.applications.proton-launch) presentMode;
    in
    {
      presentMode =
        icedosLib.mkEnumOption
          {
            path = "icedos.applications.proton-launch.presentMode";
            source = ./config.toml;
            default = presentMode;
          }
          [
            ""
            "fifo"
            "relaxed"
            "mailbox"
            "immediate"
          ];
    };

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
            any
            attrNames
            head
            last
            length
            optional
            optionalAttrs
            optionalString
            splitString
            ;

          inherit (icedosLib.bash) prelude genHelpFlags purpleString;

          inherit (config.icedos) hardware users;

          hasGamemode = config.programs.gamemode.enable;
          hasGamescope = config.programs.gamescope.enable;
          hasKde = config.services.desktopManager.plasma6.enable;
          hasMangohud = any (user: config.home-manager.users.${user}.programs.mangohud.enable) (
            attrNames users
          );
          hasNvidia = icedosLib.hasModule {
            inherit config;
            url = "github:icedos/hardware";
            name = "nvidia";
          };
          hasPowerProfilesDaemon = config.services.power-profiles-daemon.enable;

          inherit (config.icedos.applications.proton-launch) presentMode;

          packages = [ proton-launch ] ++ optional hasGamescope pkgs.gamescope;

          # Skip heavy maintenance (nix GC, fstrim, logrotate) during gameplay.
          # Uses GAME_INHIBIT lock as ExecCondition since systemd-inhibit can't gate timers.
          deferWhileGaming = {
            serviceConfig.ExecCondition = pkgs.writeShellScript "defer-while-proton-launch" ''
              ! ${pkgs.systemd}/bin/systemd-inhibit --list --no-pager \
                | ${pkgs.gnugrep}/bin/grep -q proton-launch
            '';
          };

          deferredServices = {
            systemd-tmpfiles-clean = deferWhileGaming;
          }
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
              ''
            else
              "";

          conditionalVrrHelp =
            if hasGamescope then
              ''echo -e "> ${purpleString "--vrr"}: let gamescope drive the display with adaptive sync"''
            else
              "";

          conditionalLowLatencyHelp =
            if
              (icedosLib.hasModule {
                inherit config;
                url = "github:icedos/hardware";
                name = "low-latency-vulkan-layer";
              })
            then
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
                set -o pipefail
                export LD_LIBRARY_PATH="''${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}/usr/lib32:/usr/lib"

                ${prelude}

                if [[ ${genHelpFlags { }} ]]; then
                  echo "Usage: proton-launch [OPTIONS] [--] <command> [args...]"
                  echo "Available options:"
                  echo -e "> ${purpleString "--deck"}: pretend to be a Steam Deck"
                  echo -e "> ${purpleString "--debug-logs"}: enable VKD3D/DXVK/Proton warn logging into \$XDG_RUNTIME_DIR and stop silencing output (off by default)"
                  ${conditionalGamemodeHelp}
                  ${conditionalGamescopeHelp}
                  echo -e "> ${purpleString "--gamescope-args <args>"}: pass extra args to gamescope"
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
                  echo -e "> ${purpleString "--no-write-watch"}: drop wine's memory write watches (per-game hack: verify the game still works before using it)"
                  echo -e "> ${purpleString "--present-mode <mode>"}: force the Vulkan present mode (fifo, relaxed, mailbox, immediate)${
                    if presentMode != "" then " [default: ${presentMode}]" else ""
                  }"
                  echo -e "> ${purpleString "--sdl-x11"}: force SDL to use X11 video driver"
                  echo -e "> ${purpleString "--shader-all-cores"}: use all CPU cores for DXVK shader compilation"
                  echo -e "> ${purpleString "--tear-free"}: force DXVK mailbox presentation (no tearing without vsync)"
                  echo -e "> ${purpleString "--no-tear-free"}: force DXVK relaxed-fifo presentation (may tear below refresh, but stutters less)"
                  ${conditionalVrrHelp}
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
                # VKD3D_LOG is separate from VKD3D_DEBUG; silencing one without
                # the other still spews shader compiler output during stutter.
                VKD3D_SHADER_DEBUG=none
                # winemenubuilder writes .desktop files, icons and mime entries
                # into ~/.local/share every time it runs; nothing here wants it.
                ENABLE_VK_LAYER_VALVE_steam_fossilize_1=0
                WINEDLLOVERRIDES="d3d12=n,b;dbghelp=n,b;dinput8=n,b;dsound=n,b;dwrite=n,b;dxgi=n,b;version=n,b;winhttp=n,b;wininet=n,b;winmm=n,b;winemenubuilder.exe=d''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
                # Per-game hack: breaks anything relying on wine's write tracking.
                PROTON_NO_WRITE_WATCH=0
                WINEFSYNC=1
                mesa_glthread=true
                # Single-file Mesa-DB cache: fewer files and syscalls than the
                # default multi-file layout. Discards the old cache once.
                MESA_DISK_CACHE_DATABASE=1
                ${optionalString (presentMode != "") ''
                  MESA_VK_WSI_PRESENT_MODE=${presentMode}
                ''}
                ${
                  if hasNvidia then
                    ''
                      # Stop the NVIDIA driver purging the GL shader cache between
                      # launches (CachyOS/Bazzite default). NVIDIA-only.
                      __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
                    ''
                  else
                    ""
                }
                RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

                # Auto-detect ntsync — enable if kernel supports it,
                # --no-ntsync overrides below.
                if [ -e /dev/ntsync ]; then
                  PROTON_USE_NTSYNC=1
                else
                  PROTON_USE_NTSYNC=0
                fi

                ${
                  if hasMangohud then
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
                  if
                    icedosLib.hasModule {
                      inherit config;
                      url = "github:icedos/hardware";
                      name = "monitors";
                    }
                    && (length hardware.monitors) != 0
                  then
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
                      [ $# -ge 2 ] || { echo "Missing value for --fps-limit" >&2; exit 1; }
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
                        if
                          (icedosLib.hasModule {
                            inherit config;
                            url = "github:icedos/hardware";
                            name = "low-latency-vulkan-layer";
                          })
                        then
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
                        if hasGamemode then
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
                      [ $# -ge 2 ] || { echo "Missing value for --gamescope-args" >&2; exit 1; }
                      GAMESCOPE_ARGS="$2"

                      if [[ $GAMESCOPE_ARGS =~ (^| )(-W[0-9]|-W [0-9]|-H[0-9]|-H [0-9]) ]]; then
                        DEFAULT_WIDTH=""
                        DEFAULT_HEIGHT=""
                      fi

                      if [[ $GAMESCOPE_ARGS =~ (^| )(-r[0-9]|-r [0-9]) ]]; then
                        DEFAULT_REFRESH_RATE=""
                      fi

                      shift 2
                      ;;
                    --lod-bias)
                      [ $# -ge 2 ] || { echo "Missing value for --lod-bias" >&2; exit 1; }
                      DXVK_CONFIG_OPTS="''${DXVK_CONFIG_OPTS:+$DXVK_CONFIG_OPTS;}d3d11.samplerLodBias = $2;d3d9.samplerLodBias = $2"
                      shift 2
                      ;;
                    --max-frame-latency)
                      [ $# -ge 2 ] || { echo "Missing value for --max-frame-latency" >&2; exit 1; }
                      DXVK_CONFIG_OPTS="''${DXVK_CONFIG_OPTS:+$DXVK_CONFIG_OPTS;}dxgi.maxFrameLatency = $2"
                      shift 2
                      ;;
                    --present-mode)
                      [ $# -ge 2 ] || { echo "Missing value for --present-mode" >&2; exit 1; }
                      case "$2" in
                        fifo|relaxed|mailbox|immediate) ;;
                        *)
                          echo "Invalid --present-mode: $2 (expected fifo, relaxed, mailbox or immediate)" >&2
                          exit 1
                          ;;
                      esac
                      MESA_VK_WSI_PRESENT_MODE="$2"
                      shift 2
                      ;;
                    --tear-free)
                      DXVK_CONFIG_OPTS="''${DXVK_CONFIG_OPTS:+$DXVK_CONFIG_OPTS;}dxvk.tearFree = True"
                      shift
                      ;;
                    --no-tear-free)
                      DXVK_CONFIG_OPTS="''${DXVK_CONFIG_OPTS:+$DXVK_CONFIG_OPTS;}dxvk.tearFree = False"
                      shift
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
                      # Mesa's cache is the biggest of the three; leaving it on
                      # would make this flag a half-measure.
                      MESA_SHADER_CACHE_DISABLE=1
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
                    --no-write-watch)
                      PROTON_NO_WRITE_WATCH=1
                      shift
                      ;;
                      ${
                        if hasGamescope then
                          ''
                            --vrr)
                              GAMESCOPE_ARGS="''${GAMESCOPE_ARGS:+$GAMESCOPE_ARGS }--adaptive-sync"
                              shift
                              ;;
                          ''
                        else
                          ""
                      }
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
                    -*|--*)
                      echo "Unknown arg: $1" >&2
                      exit 1
                      ;;
                    *)
                      COMMAND=("$@")
                      break
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
                __GL_SHADER_DISK_CACHE_SKIP_CLEANUP \
                GST_DEBUG \
                LOW_LATENCY_LAYER \
                LOW_LATENCY_LAYER_FORCE_DECOUPLED \
                LOW_LATENCY_LAYER_REFLEX \
                LOW_LATENCY_LAYER_SPOOF_NVIDIA \
                MESA_DISK_CACHE_DATABASE \
                MESA_SHADER_CACHE_DISABLE \
                MESA_VK_WSI_PRESENT_MODE \
                MANGOHUD_CONFIGFILE \
                MLFG_WATERMARK \
                PROTON_ENABLE_HDR \
                PROTON_ENABLE_HIDRAW \
                PROTON_ENABLE_WAYLAND \
                PROTON_FORCE_NVAPI \
                PROTON_FSR4_UPGRADE \
                PROTON_LOG \
                PROTON_LOG_DIR \
                PROTON_NO_ESYNC \
                PROTON_NO_WRITE_WATCH \
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

                # WINEDEBUG=-all only when not debugging; Proton uses
                # env.setdefault so unconditional export would neuter PROTON_LOG.
                if [ "$DEBUG_LOGS" = "0" ]; then
                  export WINEDEBUG="-all"
                fi

                [[ "$MANGOAPP" != "" && "$GAMESCOPE" != "" ]] && MANGOHUD=""

                # A crashing game or anti-cheat child otherwise dumps its whole
                # address space through systemd-coredump mid-session.
                if [ "$DEBUG_LOGS" = "0" ]; then
                  ulimit -c 0
                fi

                # Redirect stderr to tmpfs to avoid journald fsync during gameplay.
                # PROTON_LAUNCH_LOG provides a readable last-run log at no disk cost.
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
              scopebuddy = inputs.scopebuddy.packages.${final.stdenv.hostPlatform.system}.default;
            })
          ];
        }
      )
    ];

  meta.name = "proton-launch";
}
