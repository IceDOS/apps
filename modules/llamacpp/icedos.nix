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
              --reasoning-budget ${toString (builtins.floor (contextSize / reasoningBudgetDivider))} \
              ${lib.optionalString (cacheTypeK != "") "--cache-type-k ${cacheTypeK}"} \
              ${lib.optionalString (cacheTypeV != "") "--cache-type-v ${cacheTypeV}"} \
              --flash-attn ${if flashAttn then "on" else "off"} \
              ${lib.optionalString reasoningPreserve "--reasoning-preserve"} \
              ${lib.optionalString (mmproj != "") "--mmproj ${mmproj} --image-min-tokens 1024"} \
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
                  help = "Run configured model with optional --flags";

                  script = ''
                    ${icedosLib.bash.mkFlags {
                      prefix = "LLAMACPP";
                      passthroughUnknown = true;
                      flags = [
                        { name = "host"; short = "H"; type = "string"; default = host; description = "Listen address"; }
                        { name = "port"; short = "p"; type = "int"; default = port; description = "Listen port"; }
                        { name = "model"; short = "m"; type = "string"; default = model; description = "Model path"; }
                        { name = "gpu-layers"; short = "ngl"; type = "int"; default = gpuLayers; description = "GPU layers"; }
                        { name = "threads"; short = "t"; type = "int"; default = threads; description = "CPU threads"; }
                        { name = "ctx-size"; short = "c"; type = "int"; default = contextSize; description = "Context size"; }
                        { name = "batch-size"; short = "b"; type = "int"; default = batchSize; description = "Batch size"; }
                        { name = "ubatch-size"; type = "int"; default = ubatchSize; description = "Microbatch size"; }
                        { name = "cache-type-k"; short = "ctk"; type = "string"; default = cacheTypeK; description = "KV cache type for K"; }
                        { name = "cache-type-v"; short = "ctv"; type = "string"; default = cacheTypeV; description = "KV cache type for V"; }
                        { name = "mmproj"; type = "string"; default = mmproj; description = "Multimodal projector path"; }
                        { name = "prio"; type = "int"; default = prio; description = "Prioritization (0 = no priority)"; }
                        { name = "prio-batch"; type = "int"; default = prioBatch; description = "Prioritization batch size"; }
                        { name = "flash-attn"; type = "enum"; default = if flashAttn then "on" else "off"; description = "Flash attention"; choices = ["on" "off" "auto"]; }
                        { name = "reasoning-budget"; type = "int"; default = contextSize / reasoningBudgetDivider; description = "Reasoning budget tokens"; }
                        { name = "reasoning-preserve"; type = "bool"; default = reasoningPreserve; description = "Preserve reasoning trace"; }
                        { name = "detached"; short = "d"; type = "bool"; default = false; description = "Run in background"; }
                      ];
                    }}

                    # Single-session guard
                    PIDFILE="''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR unset}/icedos/llamacpp.pid"
                    if [[ -f "$PIDFILE" ]]; then
                      PID=$(cat "$PIDFILE")
                      if kill -0 "$PID" 2>/dev/null; then
                        die "llamacpp is already running (PID $PID)"
                      fi
                      rm -f "$PIDFILE"
                    fi

                    # Build override args for flags that were explicitly set
                    ARGS=()
                    if [[ "$LLAMACPP_HOST_SET" == "1" ]]; then ARGS+=(--host "$LLAMACPP_HOST"); fi
                    if [[ "$LLAMACPP_PORT_SET" == "1" ]]; then ARGS+=(--port "$LLAMACPP_PORT"); fi
                    if [[ "$LLAMACPP_MODEL_SET" == "1" ]]; then ARGS+=(--model "$LLAMACPP_MODEL"); fi
                    if [[ "$LLAMACPP_GPU_LAYERS_SET" == "1" ]]; then ARGS+=(--gpu-layers "$LLAMACPP_GPU_LAYERS"); fi
                    if [[ "$LLAMACPP_THREADS_SET" == "1" ]]; then ARGS+=(--threads "$LLAMACPP_THREADS"); fi
                    if [[ "$LLAMACPP_CTX_SIZE_SET" == "1" ]]; then ARGS+=(--ctx-size "$LLAMACPP_CTX_SIZE"); fi
                    if [[ "$LLAMACPP_BATCH_SIZE_SET" == "1" ]]; then ARGS+=(--batch-size "$LLAMACPP_BATCH_SIZE"); fi
                    if [[ "$LLAMACPP_UBATCH_SIZE_SET" == "1" ]]; then ARGS+=(--ubatch-size "$LLAMACPP_UBATCH_SIZE"); fi
                    if [[ "$LLAMACPP_CACHE_TYPE_K_SET" == "1" ]]; then ARGS+=(--cache-type-k "$LLAMACPP_CACHE_TYPE_K"); fi
                    if [[ "$LLAMACPP_CACHE_TYPE_V_SET" == "1" ]]; then ARGS+=(--cache-type-v "$LLAMACPP_CACHE_TYPE_V"); fi
                    if [[ "$LLAMACPP_MMPROJ_SET" == "1" ]]; then ARGS+=(--mmproj "$LLAMACPP_MMPROJ" --image-min-tokens 1024); fi
                    if [[ "$LLAMACPP_PRIO_SET" == "1" ]]; then ARGS+=(--prio "$LLAMACPP_PRIO"); fi
                    if [[ "$LLAMACPP_PRIO_BATCH_SET" == "1" ]]; then ARGS+=(--prio-batch "$LLAMACPP_PRIO_BATCH"); fi
                    if [[ "$LLAMACPP_FLASH_ATTN_SET" == "1" ]]; then ARGS+=(--flash-attn "$LLAMACPP_FLASH_ATTN"); fi
                    if [[ "$LLAMACPP_REASONING_BUDGET_SET" == "1" ]]; then ARGS+=(--reasoning-budget "$LLAMACPP_REASONING_BUDGET"); fi
                    if [[ "$LLAMACPP_REASONING_PRESERVE_SET" == "1" ]]; then
                      if [[ "$LLAMACPP_REASONING_PRESERVE" == "true" ]]; then
                        ARGS+=(--reasoning-preserve)
                      else
                        ARGS+=(--no-reasoning-preserve)
                      fi
                    fi
                    ARGS+=("$@")

                    if [[ "$LLAMACPP_DETACHED" == "true" ]]; then
                      nohup systemd-run --user --scope ${llamaServer} "''${ARGS[@]}" >/dev/null 2>&1 &
                    else
                      exec systemd-run --user --scope ${llamaServer} "''${ARGS[@]}"
                    fi
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
