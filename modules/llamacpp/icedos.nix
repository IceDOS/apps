{ icedosLib, lib, ... }:

{
  options.icedos.applications.llamacpp =
    let
      inherit (lib) importTOML types;

      inherit (icedosLib)
        mkAttrsOfOption
        mkBoolOption
        mkEitherOption
        mkFloatBetweenOption
        mkIntBetweenOption
        mkStrOption
        ;

      inherit ((importTOML ./config.toml).icedos.applications.llamacpp)
        batchSize
        cacheTypeK
        cacheTypeV
        contextSize
        flashAttn
        gpuLayers
        vkDisableHostVisibleVidmem
        host
        mmproj
        mmprojOffload
        model
        prio
        prioBatch
        port
        priorityUsers
        lifecycle
        lifecycleIdleSeconds
        lifecycleProvider
        lifecycleBin
        lifecycleModelId
        lifecycleModelName
        lifecycleModelReasoning
        lifecycleModelMaxTokens
        lifecycleModelThinkingLevelMap
        sleepIdleSeconds
        specType
        reasoningBudgetDivider
        reasoningPreserve
        service
        threads
        ubatchSize
        ;
    in
    {
      batchSize = mkIntBetweenOption {
        path = "icedos.applications.llamacpp.batchSize";
        source = ./config.toml;
        default = batchSize;
      } 1 1048576;
      cacheTypeK = mkStrOption { default = cacheTypeK; };
      cacheTypeV = mkStrOption { default = cacheTypeV; };
      specType = mkStrOption { default = specType; };
      # Floor of 1, not 0: llama.cpp reads 0 as "use the model's own trained
      # context", which this module cannot honour because it also feeds
      # contextSize to prime-agent's contextWindow.
      contextSize = mkIntBetweenOption {
        path = "icedos.applications.llamacpp.contextSize";
        source = ./config.toml;
        default = contextSize;
      } 1 4194304;
      flashAttn = mkBoolOption { default = flashAttn; };
      # Vulkan-only: bars llama.cpp from routing tensors through host-visible
      # device memory (the small ReBAR window). On BAR-limited cards like Navi21
      # that path collapses token generation ~3x.
      vkDisableHostVisibleVidmem = mkBoolOption { default = vkDisableHostVisibleVidmem; };
      # -1 is llama.cpp's own default ("auto") and -2 means "all"; both are
      # sentinels rather than counts.
      gpuLayers = mkIntBetweenOption {
        path = "icedos.applications.llamacpp.gpuLayers";
        source = ./config.toml;
        default = gpuLayers;
      } (-2) 1024;
      host = mkStrOption { default = host; };
      mmproj = mkStrOption { default = mmproj; };
      mmprojOffload = mkBoolOption { default = mmprojOffload; };
      model = mkStrOption { default = model; };
      # arg.cpp rejects anything outside these ranges — and they differ: --prio
      # takes low(-1), while --prio-batch starts at normal(0). Validating here
      # keeps a bad value from being caught only when the server refuses to boot.
      prio = mkIntBetweenOption {
        path = "icedos.applications.llamacpp.prio";
        source = ./config.toml;
        default = prio;
      } (-1) 3;

      prioBatch = mkIntBetweenOption {
        path = "icedos.applications.llamacpp.prioBatch";
        source = ./config.toml;
        default = prioBatch;
      } 0 3;

      port = mkIntBetweenOption {
        path = "icedos.applications.llamacpp.port";
        source = ./config.toml;
        default = port;
      } 1 65535;

      # A raised nice ceiling lets a process starve interactive work — grant it
      # only to an explicit allowlist of usernames, or the literal "all"
      # (constrained to fail on typos). Takes effect at the next login, or when
      # user@$UID.service restarts if lingering is enabled.
      #
      # pam_limits ranks a user-domain line above a group-domain one, so a name
      # listed here stops receiving group-scoped nice grants (a @pipewire -19,
      # say) and gets this ceiling instead.
      priorityUsers = mkEitherOption { default = priorityUsers; } (
        (types.addCheck types.str (v: v == "all"))
        // {
          description = ''the literal "all"'';
        }
      ) (types.listOf types.str);

      # Install prime-agent's lifecycle extension. Owned here rather than by
      # prime-agent: it drives this module's own serve/stop and /slots, and
      # keeping both idle mechanisms in one module means the conflict between
      # them can be asserted without a cross-module read.
      lifecycle = mkBoolOption { default = lifecycle; };

      lifecycleIdleSeconds = mkIntBetweenOption {
        path = "icedos.applications.llamacpp.lifecycleIdleSeconds";
        source = ./config.toml;
        default = lifecycleIdleSeconds;
      } 0 86400;

      lifecycleProvider = mkStrOption { default = lifecycleProvider; };
      lifecycleBin = mkStrOption { default = lifecycleBin; };

      # Registers this server with prime-agent. api/baseUrl/contextWindow are
      # derived from the options above so they cannot drift from what the server
      # is actually running; only what the module cannot know is settable.
      lifecycleModelId = mkStrOption { default = lifecycleModelId; };
      lifecycleModelName = mkStrOption { default = lifecycleModelName; };
      lifecycleModelReasoning = mkBoolOption { default = lifecycleModelReasoning; };

      lifecycleModelMaxTokens = mkIntBetweenOption {
        path = "icedos.applications.llamacpp.lifecycleModelMaxTokens";
        source = ./config.toml;
        default = lifecycleModelMaxTokens;
      } 1 1048576;

      # Model-specific, so the module cannot derive it. See prime-agent's
      # thinkingLevelMap for the accepted keys.
      lifecycleModelThinkingLevelMap = mkAttrsOfOption {
        default = lifecycleModelThinkingLevelMap;
      } (types.nullOr types.str);

      # Int, not number: arg.cpp parses with std::stoi, so a float would be
      # silently truncated (2.5 -> 2) or rejected outright (0.5 -> "cannot be 0").
      sleepIdleSeconds = mkIntBetweenOption {
        path = "icedos.applications.llamacpp.sleepIdleSeconds";
        source = ./config.toml;
        default = sleepIdleSeconds;
      } (-1) 86400;

      # Bounded on the option, not by an assertion: contextSize is divided by
      # this while building the serve script, which happens before assertions
      # are reported — a 0 aborts with a bare "division by zero" instead.
      reasoningBudgetDivider = mkFloatBetweenOption {
        path = "icedos.applications.llamacpp.reasoningBudgetDivider";
        source = ./config.toml;
        default = reasoningBudgetDivider;
      } 0.001 1024;
      reasoningPreserve = mkBoolOption { default = reasoningPreserve; };
      service = mkBoolOption { default = service; };
      # -1 means every core; anything below that is meaningless to llama.cpp.
      threads = mkIntBetweenOption {
        path = "icedos.applications.llamacpp.threads";
        source = ./config.toml;
        default = threads;
      } (-1) 4096;
      ubatchSize = mkIntBetweenOption {
        path = "icedos.applications.llamacpp.ubatchSize";
        source = ./config.toml;
        default = ubatchSize;
      } 1 1048576;
    };

  outputs.nixosModules =
    { repoUrl, ... }:
    [
      (
        {
          config,
          pkgs,
          lib,
          ...
        }:

        let
          inherit (lib)
            attrNames
            concatMap
            elem
            filterAttrs
            mkIf
            optionals
            ;
          inherit (config.icedos) users;

          inherit (config.icedos.applications.llamacpp)
            batchSize
            cacheTypeK
            cacheTypeV
            contextSize
            flashAttn
            gpuLayers
            host
            vkDisableHostVisibleVidmem
            mmproj
            mmprojOffload
            model
            prio
            prioBatch
            port
            priorityUsers
            lifecycle
            lifecycleIdleSeconds
            lifecycleProvider
            lifecycleBin
            lifecycleModelId
            lifecycleModelName
            lifecycleModelReasoning
            lifecycleModelMaxTokens
            lifecycleModelThinkingLevelMap
            sleepIdleSeconds
            specType
            reasoningBudgetDivider
            reasoningPreserve
            service
            threads
            ubatchSize
            ;

          llamaCpp = pkgs.llama-cpp-vulkan;

          # host is what the server binds; these are what a client dials. A
          # wildcard bind is not an address, and IPv6 needs brackets in a URL.
          clientHost =
            if host == "0.0.0.0" then
              "127.0.0.1"
            else if host == "::" || host == "[::]" then
              "[::1]"
            else if lib.hasInfix ":" host && !(lib.hasPrefix "[" host) then
              "[${host}]"
            else
              host;

          # The extension only means anything if prime-agent is around to load it.
          hasPrimeAgent = icedosLib.hasModule {
            inherit config repoUrl;
            name = "prime-agent";
          };

          # Also on the model: an extension that can never start a server still
          # registers before_provider_request, and prime-agent parks its
          # Idempotency-Key reuse whenever any handler exists — so an inert
          # install would make every provider's auto-retry billable.
          lifecycleEnabled = lifecycle && hasPrimeAgent && model != "" && lifecycleModelId != "";

          # The markers sit inside TypeScript string literals so the template
          # still parses on its own; jsStr escapes a value for that context,
          # which escapeShellArg (which protects the builder, not the literal)
          # does not do.
          jsStr =
            v: lib.escapeShellArg (lib.replaceStrings [ "\\" "\"" "\n" "\r" ] [ "\\\\" "\\\"" "\\n" "\\r" ] v);

          lifecycleSrc = pkgs.runCommand "prime-agent-llamacpp-lifecycle.ts" { } ''
            cp ${./extensions/llamacpp-lifecycle.ts} $out
            chmod +w $out
            substituteInPlace $out \
              --replace-fail "@llamacppUrl@" ${jsStr "http://${clientHost}:${toString port}"} \
              --replace-fail "@llamacppBin@" ${jsStr lifecycleBin} \
              --replace-fail "@llamacppProvider@" ${jsStr lifecycleProvider} \
              --replace-fail "@llamacppIdleSeconds@" ${jsStr (toString lifecycleIdleSeconds)}

            if ${pkgs.gnugrep}/bin/grep -qE '@[a-zA-Z_][0-9A-Za-z_-]*@' $out; then
              echo "unsubstituted placeholder left in llamacpp-lifecycle.ts" >&2
              exit 1
            fi
          '';

          llamaServer = pkgs.writeShellScript "llamacpp-serve" ''
            ${lib.optionalString vkDisableHostVisibleVidmem "export GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1"}
            RUNTIME="''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR unset}"
            ${pkgs.coreutils}/bin/mkdir -p "$RUNTIME/icedos"

            # O_EXCL, because serve's guard runs before this wrapper exists: two
            # callers racing both pass that guard, and without an atomic claim
            # here both would start a server, the loser dying on the port and
            # leaving the pidfile naming a corpse. This wrapper is the sole
            # authority on the pidfile — nothing removes it on exit, so it also
            # has to recognise its own leftovers or a restart could never claim.
            PIDFILE="$RUNTIME/icedos/llamacpp.pid"
            claim() { (set -C; echo "$$" >"$PIDFILE") 2>/dev/null; }

            if ! claim; then
              OWNER=$(${pkgs.coreutils}/bin/cat "$PIDFILE" 2>/dev/null || true)
              if [[ "$OWNER" =~ ^[1-9][0-9]*$ ]] &&
                 kill -0 "$OWNER" 2>/dev/null &&
                 ${pkgs.gnugrep}/bin/grep -qa 'llama-server\|llamacpp-serve' \
                   "/proc/$OWNER/cmdline" 2>/dev/null; then
                echo "llamacpp is already running (PID $OWNER)" >&2
                exit 1
              fi

              # Stale: the previous server died without cleaning up. mkdir is
              # atomic, so exactly one wrapper does the removal — an unguarded
              # rm here would delete a fresh claim another wrapper had just won.
              if ${pkgs.coreutils}/bin/mkdir "$PIDFILE.recover" 2>/dev/null; then
                ${pkgs.coreutils}/bin/rm -f "$PIDFILE"
                claim || true
                ${pkgs.coreutils}/bin/rmdir "$PIDFILE.recover" 2>/dev/null || true
              else
                # Someone else is recovering; give them a moment and re-try.
                ${pkgs.coreutils}/bin/sleep 0.3
              fi

              if [[ "$(${pkgs.coreutils}/bin/cat "$PIDFILE" 2>/dev/null)" != "$$" ]]; then
                echo "llamacpp is already starting" >&2
                exit 1
              fi
            fi

            # Wait for dmemcg-booster to enable dmem on our scope. Store-pinned
            # rather than ambient so the closure is explicit and the wrapper is
            # immune to PATH or awk-implementation changes.
            DMEM_DEVICE=$(${pkgs.gawk}/bin/awk '{print $1}' /sys/fs/cgroup/dmem.capacity 2>/dev/null) || true
            if [ -n "$DMEM_DEVICE" ]; then
              CGROUP_PATH=$(${pkgs.gnused}/bin/sed 's/0:://' /proc/$$/cgroup 2>/dev/null) || true
              dmem_path="/sys/fs/cgroup/''${CGROUP_PATH}"
              for _ in $(${pkgs.coreutils}/bin/seq 1 10); do
                [ -f "$dmem_path/dmem.low" ] && break
                ${pkgs.coreutils}/bin/sleep 1
              done
              if [ -f "$dmem_path/dmem.low" ]; then
                echo "''${DMEM_DEVICE} max" > "$dmem_path/dmem.low" 2>/dev/null || true
                ( while ${pkgs.coreutils}/bin/sleep 5; do
                    kill -0 "$$" 2>/dev/null || exit 0
                    CURRENT=$(${pkgs.gawk}/bin/awk -v dev="''${DMEM_DEVICE}" '$1==dev {print $2}' "$dmem_path/dmem.current" 2>/dev/null)
                    [ -n "$CURRENT" ] && echo "''${DMEM_DEVICE} $CURRENT" > "$dmem_path/dmem.min" 2>/dev/null
                  done ) &
              fi
            fi

            exec ${pkgs.util-linux}/bin/chrt --other 0 ${llamaCpp}/bin/llama-server \
              -m ${lib.escapeShellArg model} \
              --host ${lib.escapeShellArg host} \
              --port ${toString port} \
              -ngl ${toString gpuLayers} \
              -t ${toString threads} \
              -b ${toString batchSize} \
              -ub ${toString ubatchSize} \
              --prio ${toString prio} \
              --prio-batch ${toString prioBatch} \
              --ctx-size ${toString contextSize} \
              --reasoning-budget ${
                toString (lib.max 1 (builtins.floor (contextSize / reasoningBudgetDivider)))
              } \
              ${lib.optionalString (cacheTypeK != "") "--cache-type-k ${lib.escapeShellArg cacheTypeK}"} \
              ${lib.optionalString (cacheTypeV != "") "--cache-type-v ${lib.escapeShellArg cacheTypeV}"} \
              ${lib.optionalString (specType != "") "--spec-type ${lib.escapeShellArg specType}"} \
              --flash-attn ${if flashAttn then "on" else "off"} \
              ${lib.optionalString (sleepIdleSeconds > 0) "--sleep-idle-seconds ${toString sleepIdleSeconds}"} \
              ${lib.optionalString reasoningPreserve "--reasoning-preserve"} \
              ${
                lib.optionalString (mmproj != "") "--mmproj ${lib.escapeShellArg mmproj} --image-min-tokens 1024"
              } \
              ${lib.optionalString (mmproj != "" && !mmprojOffload) "--no-mmproj-offload"} \
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
                        {
                          name = "host";
                          short = "H";
                          type = "string";
                          default = host;
                          description = "Listen address";
                        }
                        {
                          name = "port";
                          short = "p";
                          type = "int";
                          default = port;
                          description = "Listen port";
                        }
                        {
                          name = "model";
                          short = "m";
                          type = "string";
                          default = model;
                          description = "Model path";
                        }
                        {
                          name = "gpu-layers";
                          short = "ngl";
                          type = "int";
                          default = gpuLayers;
                          description = "GPU layers";
                        }
                        {
                          name = "threads";
                          short = "t";
                          type = "int";
                          default = threads;
                          description = "CPU threads";
                        }
                        {
                          name = "ctx-size";
                          short = "c";
                          type = "int";
                          default = contextSize;
                          description = "Context size";
                        }
                        {
                          name = "batch-size";
                          short = "b";
                          type = "int";
                          default = batchSize;
                          description = "Batch size";
                        }
                        {
                          name = "ubatch-size";
                          type = "int";
                          default = ubatchSize;
                          description = "Microbatch size";
                        }
                        {
                          name = "cache-type-k";
                          short = "ctk";
                          type = "string";
                          default = cacheTypeK;
                          description = "KV cache type for K";
                        }
                        {
                          name = "cache-type-v";
                          short = "ctv";
                          type = "string";
                          default = cacheTypeV;
                          description = "KV cache type for V";
                        }
                        {
                          name = "spec-type";
                          type = "string";
                          default = specType;
                          description = "Speculative decoding types";
                        }
                        {
                          name = "mmproj";
                          type = "string";
                          default = mmproj;
                          description = "Multimodal projector path";
                        }
                        {
                          name = "prio";
                          type = "int";
                          default = prio;
                          description = "Process/thread priority level (-1 to 3)";
                        }
                        {
                          name = "prio-batch";
                          type = "int";
                          default = prioBatch;
                          description = "Batch thread priority level (0-3)";
                        }
                        {
                          name = "flash-attn";
                          type = "enum";
                          default = if flashAttn then "on" else "off";
                          description = "Flash attention";
                          choices = [
                            "on"
                            "off"
                            "auto"
                          ];
                        }
                        {
                          name = "reasoning-budget";
                          type = "int";
                          default = lib.max 1 (builtins.floor (contextSize / reasoningBudgetDivider));
                          description = "Reasoning budget tokens";
                        }
                        {
                          name = "reasoning-preserve";
                          type = "bool";
                          default = reasoningPreserve;
                          description = "Preserve reasoning trace";
                        }
                        {
                          name = "detached";
                          short = "d";
                          type = "bool";
                          default = false;
                          description = "Run in background";
                        }
                      ];
                    }}

                    # A courtesy check only, for a readable error before the model
                    # loads. It deliberately does NOT remove a stale pidfile: that
                    # decision and the removal cannot be made atomic against a
                    # concurrent wrapper, and racing it let two servers start. The
                    # wrapper's O_EXCL claim is the sole authority.
                    PIDFILE="''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR unset}/icedos/llamacpp.pid"
                    if [[ -f "$PIDFILE" ]]; then
                      PID=$(${pkgs.coreutils}/bin/cat "$PIDFILE" 2>/dev/null || true)
                      if [[ "$PID" =~ ^[1-9][0-9]*$ ]] &&
                         kill -0 "$PID" 2>/dev/null &&
                         ${pkgs.gnugrep}/bin/grep -qa 'llama-server\|llamacpp-serve' \
                           "/proc/$PID/cmdline" 2>/dev/null; then
                        die "llamacpp is already running (PID $PID)"
                      fi
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
                    if [[ "$LLAMACPP_SPEC_TYPE_SET" == "1" ]]; then ARGS+=(--spec-type "$LLAMACPP_SPEC_TYPE"); fi
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
                      # RUNTIME belongs to the wrapper, and the redirect runs before it can mkdir.
                      ${pkgs.coreutils}/bin/mkdir -p "$XDG_RUNTIME_DIR/icedos"
                      nohup systemd-run --user --scope ${llamaServer} "''${ARGS[@]}" >"$XDG_RUNTIME_DIR/icedos/llamacpp.log" 2>&1 &
                    else
                      exec systemd-run --user --scope ${llamaServer} "''${ARGS[@]}"
                    fi
                  '';
                }

                {
                  command = "stop";
                  help = "Stop the running server and free its VRAM";

                  script = ''
                    SLEEP=${pkgs.coreutils}/bin/sleep
                    SYSTEMCTL=${pkgs.systemd}/bin/systemctl
                    GREP=${pkgs.gnugrep}/bin/grep
                    CAT=${pkgs.coreutils}/bin/cat
                    RM=${pkgs.coreutils}/bin/rm

                    # is_help_flag is true for the empty string, so it can only be
                    # consulted once we know an argument was actually given.
                    if [[ $# -gt 0 ]]; then
                      if [[ -n "$1" ]] && is_help_flag "$1"; then
                        echo "Usage: icedos llamacpp stop"
                        exit 0
                      fi
                      die "stop takes no arguments"
                    fi

                    # Killing the unit's MainPID behind systemd's back makes the
                    # SIGKILL escalation look like a failure, and Restart= brings
                    # the server straight back up. ActiveState is the right gate:
                    # is-active returns non-zero during the auto-restart window
                    # (where stopping is exactly what's wanted), while unit
                    # existence is true even for a unit that is not running —
                    # which would send every `stop` down this branch when
                    # service = true, leaving a hand-started server holding VRAM.
                    # Matched positively: `failed`, `inactive` and the empty string
                    # a systemctl error leaves behind must all fall through to the
                    # pidfile path, or a hand-started server is left holding VRAM
                    # while this reports success.
                    PIDFILE="''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR unset}/icedos/llamacpp.pid"

                    # The pidfile is the only handle this command has, so before
                    # reporting "not running" make sure nothing is actually
                    # serving — otherwise a server whose pidfile was lost keeps
                    # its ~13 GiB and the caller is told it is gone.
                    orphaned() {
                      ${pkgs.curl}/bin/curl -sf -m 2 -o /dev/null \
                        http://${clientHost}:${toString port}/health
                    }

                    STATE=$("$SYSTEMCTL" --user show -P ActiveState llamacpp 2>/dev/null) || STATE=""
                    case "$STATE" in
                      active | activating | reloading | refreshing | deactivating | maintenance)
                        "$SYSTEMCTL" --user stop llamacpp || die "failed to stop the llamacpp user unit"
                        # The unit's ExecStart writes the pidfile and nothing
                        # removes it; leaving it would let a later hand-run serve
                        # start outside systemd and collide with the unit.
                        "$RM" -f "$PIDFILE"
                        echo "llamacpp stopped (systemd unit)"
                        exit 0
                        ;;
                    esac

                    if [[ ! -f "$PIDFILE" ]]; then
                      if orphaned; then
                        die "a llamacpp server is serving ${clientHost}:${toString port} but no pidfile identifies it; stop it by hand"
                      fi
                      echo "llamacpp is not running"
                      exit 0
                    fi

                    PID=$("$CAT" "$PIDFILE" 2>/dev/null || true)
                    # Unvalidated this would be catastrophic: `kill -TERM -1` signals
                    # every process the user owns, and this script escalates to KILL.
                    if [[ ! "$PID" =~ ^[1-9][0-9]*$ ]]; then
                      "$RM" -f "$PIDFILE"
                      if orphaned; then
                        die "a llamacpp server is serving ${host}:${toString port} but no pidfile identifies it; stop it by hand"
                      fi
                      echo "llamacpp is not running (invalid pidfile removed)"
                      exit 0
                    fi

                    # serve installs no exit trap, so a stale pidfile can outlive the
                    # server and its pid be recycled onto something unrelated.
                    #
                    # cmdline, not comm: the pidfile is written by the wrapper before
                    # it execs llama-server, and during that window comm is the
                    # wrapper's own truncated store name. cmdline also reads empty
                    # for a zombie or a process mid-teardown, where `kill -0` still
                    # succeeds — so this doubles as the liveness test.
                    # Identity: is this pid still the server we wrote down?
                    identity() {
                      kill -0 "$PID" 2>/dev/null &&
                        "$GREP" -qa 'llama-server\|llamacpp-serve' "/proc/$PID/cmdline" 2>/dev/null
                    }

                    # Liveness: /proc/PID survives until the task is reaped, so
                    # this stays true through exit_files() — where the DRM fd,
                    # and the VRAM with it, is actually released. cmdline empties
                    # earlier, at exit_mm(), which would let the next serve race
                    # a half-freed GPU context.
                    running() {
                      [[ -e "/proc/$PID" ]] &&
                        [[ "$("$CAT" "/proc/$PID/stat" 2>/dev/null)" != *') Z '* ]]
                    }

                    if ! identity; then
                      "$RM" -f "$PIDFILE"
                      if orphaned; then
                        die "a llamacpp server is serving ${host}:${toString port} but no pidfile identifies it; stop it by hand"
                      fi
                      echo "llamacpp is not running (stale pidfile removed)"
                      exit 0
                    fi

                    kill -TERM "$PID" 2>/dev/null || true

                    # llama-server unmaps the model on SIGTERM; give it time before
                    # escalating, or the next serve races a half-freed GPU context.
                    # Measured at 32.5 s with a request in flight, so the budget is
                    # sized against systemd's DefaultTimeoutStopSec (90 s) rather
                    # than guessed. Each turn costs a little over 0.1 s once
                    # running()'s fork is counted, so this lands around 95 s.
                    i=0
                    while ((i++ < 900)); do
                      running || break
                      "$SLEEP" 0.1
                    done

                    if running; then
                      kill -KILL "$PID" 2>/dev/null || true
                      i=0
                      while ((i++ < 50)); do
                        running || break
                        "$SLEEP" 0.1
                      done
                    fi

                    # Report what actually happened, and keep the pidfile if it did
                    # not die: removing it would hide the surviving server from
                    # serve's guard, which would then start a second one.
                    if running; then
                      die "llamacpp (PID $PID) did not exit; VRAM is still held"
                    fi

                    "$RM" -f "$PIDFILE"
                    echo "llamacpp stopped (PID $PID)"
                  '';
                }
              ];
            }
          ];

          # Structurally omitted rather than mkIf'd: mkIf guards the value but
          # the option path is still resolved, so defining these while
          # prime-agent is absent aborts with "The option ... does not exist".
          icedos.applications = lib.optionalAttrs hasPrimeAgent {
            # This module serves models on the local GPU, so it is the one that
            # knows its provider should be metered rather than billed per token.
            # listOf merges, so a user adding another provider keeps this one.
            prime-agent.powerProviders = lib.optional (model != "") lifecycleProvider;

            # The provider block prime-agent needs, emitted from the module that
            # runs the server — the counterpart of the opencode provider below.
            # A local model has no per-token price, so cost is zero and the power
            # meter reports the real electricity instead.
            prime-agent.providers = lib.optionalAttrs (model != "") {
              ${lifecycleProvider} = {
                api = "openai-completions";
                apiKey = "no-key";
                baseUrl = "http://${clientHost}:${toString port}/v1";

                models = lib.optional (lifecycleModelId != "") {
                  id = lifecycleModelId;
                  name = if lifecycleModelName != "" then lifecycleModelName else lifecycleModelId;
                  reasoning = lifecycleModelReasoning;
                  contextWindow = contextSize;
                  maxTokens = lifecycleModelMaxTokens;
                  # A projector is what makes the server accept images at all.
                  input = [ "text" ] ++ lib.optional (mmproj != "") "image";

                  cost = {
                    input = 0;
                    output = 0;
                    cacheRead = 0;
                    cacheWrite = 0;
                  };

                  thinkingLevelMap = lifecycleModelThinkingLevelMap;
                };
              };
            };
          };

          assertions = [
            {
              # llama.cpp rejects an unknown type at startup, which the lifecycle
              # extension only surfaces as a server that never becomes healthy.
              assertion =
                specType == ""
                || lib.all (
                  x:
                  builtins.elem x [
                    "none"
                    "draft-simple"
                    "draft-eagle3"
                    "draft-mtp"
                    "draft-dflash"
                    "draft-dspark"
                    "ngram-simple"
                    "ngram-map-k"
                    "ngram-map-k4v"
                    "ngram-mod"
                    "ngram-cache"
                  ]
                ) (lib.splitString "," specType);
              message = ''
                icedos.applications.llamacpp.specType must be a comma-separated
                list of llama.cpp --spec-type values: none, draft-simple,
                draft-eagle3, draft-mtp, draft-dflash, draft-dspark,
                ngram-simple, ngram-map-k, ngram-map-k4v, ngram-mod or
                ngram-cache.
              '';
            }
            {
              # An empty name yields a provider literally called "" in
              # models.json, and powerProviders = [""] which the meter drops —
              # metering and the lifecycle both silently do nothing.
              assertion = lib.match "[A-Za-z0-9._-]+" lifecycleProvider != null;
              message = ''
                icedos.applications.llamacpp.lifecycleProvider must be a
                non-empty provider name of letters, digits, dots, underscores or
                hyphens; it keys prime-agent's provider table.
              '';
            }
            {
              # The unit autostarts at graphical-session.target while the
              # extension stops the server, after which serve --detached starts
              # a transient scope outside the unit and systemd reports inactive
              # for a server that is running.
              assertion = !(service && lifecycleEnabled);
              message = ''
                icedos.applications.llamacpp.service cannot be combined with
                lifecycle: the extension starts and stops the server itself, so
                the systemd unit ends up fighting it. Pick one owner.
              '';
            }
            {
              # /slots is not on llama.cpp's bypass_sleep list, so the extension's
              # polling wakes a sleeping server every 15s and resets its idle
              # timer — the two settings cancel each other out.
              assertion = !lifecycleEnabled || sleepIdleSeconds <= 0;
              message = ''
                icedos.applications.llamacpp.lifecycle cannot be combined with
                sleepIdleSeconds > 0: the extension polls /slots, which wakes a
                sleeping server. Pick one idle mechanism.
              '';
            }
            {
              # An allowlist, so a name nobody owns is a typo.
              assertion = priorityUsers == "all" || lib.all (n: users ? ${n}) priorityUsers;
              message = ''
                icedos.applications.llamacpp.priorityUsers names users that
                icedos.users does not declare: ${
                  lib.concatStringsSep ", " (lib.filter (n: !(users ? ${n})) priorityUsers)
                }
              '';
            }
          ];

          # `--prio` makes llama.cpp call setpriority() with a negative nice value,
          # which a user session cannot do until RLIMIT_NICE is raised here.
          # pam_limits applies at session open, so this takes effect at the next
          # login — or, with lingering enabled, only when user@$UID.service
          # restarts, since that manager outlives logout and carries the limits
          # the service = true path inherits.
          #
          # This deliberately does NOT cover the thread priorities: ggml puts its
          # workers on SCHED_FIFO 40/80/90 for medium/high/realtime, which needs
          # RLIMIT_RTPRIO. Unbounded SCHED_FIFO across every core can lock a
          # desktop out of its own input handling, so those calls are left to fail.
          security.pam.loginLimits =
            let
              # ggml_sched_priority: low = -1, normal = 0, medium = 1, high = 2,
              # realtime = 3 (ggml.h), mapped to nice in common.cpp.
              niceOf =
                p:
                if p >= 3 then
                  -20
                else if p == 2 then
                  -10
                else if p == 1 then
                  -5
                else
                  0;

              # Only `--prio` reaches setpriority(); `--prio-batch` feeds the
              # threadpool alone, so it cannot justify a nice grant.
              nice = niceOf prio;

              # "all" raises the ceiling for every user; otherwise an explicit list.
              priorityFor = n: priorityUsers == "all" || elem n priorityUsers;
              # System users have no interactive session to raise a limit for.
              selected = attrNames (filterAttrs (n: u: (u.isNormalUser or false) && priorityFor n) users);
            in
            optionals (nice < 0) (
              concatMap (user: [
                {
                  domain = user;
                  type = "hard";
                  item = "nice";
                  value = toString nice;
                }

                {
                  domain = user;
                  type = "soft";
                  item = "nice";
                  value = toString nice;
                }
              ]) selected
            );

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
            (
              { config, lib, ... }:
              let
                # The already-resolved agent dir, as prime-agent publishes it.
                # NOT config.icedos.applications.prime-agent.dataDir: `config`
                # here is the home-manager config, which has no `icedos`
                # attribute, and that option is a raw string still needing the
                # $XDG/~ expansion prime-agent applies to it.
                dataDir = config.home.sessionVariables.PRIME_AGENT_CODING_AGENT_DIR;
                relDataDir = lib.removePrefix (config.home.homeDirectory + "/") dataDir;
              in
              # home-manager.sharedModules runs for every user, but only
              # prime-agent's own users get this variable — without the guard the
              # extension lands in a home with no prime-agent config, and the
              # dataDir read above would throw for that user.
              lib.mkIf (lifecycleEnabled && config.home.sessionVariables ? PRIME_AGENT_CODING_AGENT_DIR) {
                home.file."${relDataDir}/extensions/llamacpp-lifecycle.ts".source = lifecycleSrc;
              }
            )
            {
              programs.opencode.settings.provider.llamacpp = {
                npm = "@ai-sdk/openai-compatible";
                name = "llama.cpp (Vulkan)";
                options = {
                  baseURL = "http://${clientHost}:${toString port}/v1";
                  apiKey = "no-key";
                };

                # Derived from the same options as the prime-agent provider, so
                # the advertised model cannot drift from the one being served —
                # this block previously named a model the module had stopped
                # shipping, with an output cap equal to the whole context.
                models = lib.optionalAttrs (model != "" && lifecycleModelId != "") {
                  ${lifecycleModelId} = {
                    name = if lifecycleModelName != "" then lifecycleModelName else lifecycleModelId;
                    reasoning = lifecycleModelReasoning;
                    tool_call = true;
                    images = mmproj != "";
                    limit = {
                      context = contextSize;
                      output = lifecycleModelMaxTokens;
                    };
                  };
                };
              };
            }
          ];

          icedos.system.tips.list = [
            "icedos llamacpp serve runs an AI model on your own machine."
            "icedos llamacpp stop shuts the model down and frees your graphics memory."
          ]
          ++ optionals service [
            "Your local AI model server starts on its own at boot."
          ];
        }
      )
    ];

  meta.name = "llamacpp";
}
