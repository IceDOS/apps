{ icedosLib, lib, ... }:

{
  options.icedos.applications.llamacpp =
    let
      inherit (lib) importTOML;

      inherit (icedosLib)
        mkBoolOption
        mkNumberOption
        mkStrOption
        ;

      inherit ((importTOML ./config.toml).icedos.applications.llamacpp)
        batchSize
        cacheTypeK
        cacheTypeV
        contextSize
        flashAttn
        gpuLayers
        host
        mmproj
        model
        prio
        prioBatch
        port
        reasoningBudgetDivider
        reasoningPreserve
        service
        threads
        ubatchSize
        ;
    in
    {
      batchSize = mkNumberOption { default = batchSize; };
      cacheTypeK = mkStrOption { default = cacheTypeK; };
      cacheTypeV = mkStrOption { default = cacheTypeV; };
      contextSize = mkNumberOption { default = contextSize; };
      flashAttn = mkBoolOption { default = flashAttn; };
      gpuLayers = mkNumberOption { default = gpuLayers; };
      host = mkStrOption { default = host; };
      mmproj = mkStrOption { default = mmproj; };
      model = mkStrOption { default = model; };
      prio = mkNumberOption { default = prio; };
      prioBatch = mkNumberOption { default = prioBatch; };
      port = mkNumberOption { default = port; };
      reasoningBudgetDivider = mkNumberOption { default = reasoningBudgetDivider; };
      reasoningPreserve = mkBoolOption { default = reasoningPreserve; };
      service = mkBoolOption { default = service; };
      threads = mkNumberOption { default = threads; };
      ubatchSize = mkNumberOption { default = ubatchSize; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          pkgs,
          lib,
          ...
        }:

        let
          inherit (lib) mkIf;

          inherit (config.icedos.applications.llamacpp)
            batchSize
            cacheTypeK
            cacheTypeV
            contextSize
            flashAttn
            gpuLayers
            host
            mmproj
            model
            prio
            prioBatch
            port
            reasoningBudgetDivider
            reasoningPreserve
            service
            threads
            ubatchSize
            ;

          llamaCpp = pkgs.llama-cpp-vulkan;

          llamaServer = pkgs.writeShellScript "llamacpp-serve" ''
            mkdir -p "$XDG_RUNTIME_DIR/icedos"
            echo "$$" >"$XDG_RUNTIME_DIR/icedos/llamacpp.pid"

            # Wait for dmemcg-booster to enable dmem on our scope
            DMEM_DEVICE=$(awk '{print $1}' /sys/fs/cgroup/dmem.capacity 2>/dev/null) || true
            if [ -n "$DMEM_DEVICE" ]; then
              CGROUP_PATH=$(sed 's/0:://' /proc/$$/cgroup 2>/dev/null) || true
              dmem_path="/sys/fs/cgroup/''${CGROUP_PATH}"
              for _ in $(seq 1 10); do
                [ -f "$dmem_path/dmem.low" ] && break
                sleep 1
              done
              if [ -f "$dmem_path/dmem.low" ]; then
                echo "''${DMEM_DEVICE} max" > "$dmem_path/dmem.low" 2>/dev/null || true
                ( while sleep 5; do
                    kill -0 "$$" 2>/dev/null || exit 0
                    CURRENT=$(awk -v dev="''${DMEM_DEVICE}" '$1==dev {print $2}' "$dmem_path/dmem.current" 2>/dev/null)
                    [ -n "$CURRENT" ] && echo "''${DMEM_DEVICE} $CURRENT" > "$dmem_path/dmem.min" 2>/dev/null
                  done ) &
              fi
            fi

            exec ${llamaCpp}/bin/llama-server \
              -m "${model}" \
              --host ${host} \
              --port ${toString port} \
              -ngl ${toString gpuLayers} \
              -t ${toString threads} \
              -b ${toString batchSize} \
              -ub ${toString ubatchSize} \
              --prio ${toString prio} \
              --prio-batch ${toString prioBatch} \
              --ctx-size ${toString contextSize} \
              --reasoning-budget ${toString (contextSize / reasoningBudgetDivider)} \
              ${lib.optionalString (cacheTypeK != "") "--cache-type-k ${cacheTypeK}"} \
              ${lib.optionalString (cacheTypeV != "") "--cache-type-v ${cacheTypeV}"} \
              ${lib.optionalString flashAttn "--flash-attn"} \
              ${lib.optionalString reasoningPreserve "--reasoning-preserve"} \
              ${lib.optionalString (mmproj != "") "--mmproj ${mmproj}"} \
              ${lib.optionalString (mmproj != "") "--image-min-tokens 1024"} \
              "$@"
          '';
        in
        {
          environment.systemPackages = [
            llamaCpp
          ];

          icedos.system.toolset.commands = [
            {
              command = "llamacpp";
              help = "print llamacpp related commands";

              commands = [
                {
                  command = "serve";
                  help = "Run configured model";

                  script = ''
                    case "$1" in
                      "")
                        exec systemd-run --user --scope ${llamaServer}
                        ;;
                      -d|--detached)
                        nohup systemd-run --user --scope ${llamaServer} 2>&1 >/dev/null &
                        ;;
                      *)
                        die "unknown arg: $1"
                        ;;
                    esac
                  '';
                }
              ];
            }
          ];

          systemd.user.services.llamacpp = mkIf (service && model != "") {
            unitConfig = {
              Description = "llama.cpp server (Vulkan)";
              After = "graphical-session.target";
            };

            wantedBy = [ "graphical-session.target" ];

            serviceConfig = {
              ExecStart = "${llamaServer}";
              Restart = "on-failure";
              RestartSec = 5;
            };
          };

          home-manager.sharedModules = [
            {
              programs.opencode.settings.provider.llamacpp = {
                npm = "@ai-sdk/openai-compatible";
                name = "llama.cpp (Vulkan)";
                options = {
                  baseURL = "http://${host}:${toString port}/v1";
                  apiKey = "no-key";
                };

                models.ternary-bonsai-27b = {
                  name = "Ternary Bonsai 27B Q2_0";
                  reasoning = true;
                  tool_call = true;
                  images = true;
                  limit = {
                    context = contextSize;
                    output = contextSize;
                  };
                };
              };
            }
          ];
        }
      )
    ];

  meta.name = "llamacpp";
}
