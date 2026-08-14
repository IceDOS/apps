{ icedosLib, lib, ... }:

{
  options.icedos.applications.agent-memory =
    let
      inherit (lib) importTOML;

      inherit (icedosLib)
        mkBoolOption
        mkNumberOption
        mkStrListOption
        mkStrOption
        ;

      inherit ((importTOML ./config.toml).icedos.applications.agent-memory)
        coreImage
        corePort
        envFile
        hubImage
        knowledgePort
        llmBaseUrl
        llmModel
        llmProtocol
        panelPort
        promptMode
        pullPolicy
        service
        user
        users
        ;
    in
    {
      coreImage = mkStrOption { default = coreImage; };
      corePort = mkNumberOption { default = corePort; };
      envFile = mkStrOption { default = envFile; };
      hubImage = mkStrOption { default = hubImage; };
      knowledgePort = mkNumberOption { default = knowledgePort; };
      llmBaseUrl = mkStrOption { default = llmBaseUrl; };
      llmModel = mkStrOption { default = llmModel; };
      llmProtocol = mkStrOption { default = llmProtocol; };
      panelPort = mkNumberOption { default = panelPort; };
      promptMode = mkStrOption { default = promptMode; };
      pullPolicy = mkStrOption { default = pullPolicy; };
      service = mkBoolOption { default = service; };
      user = mkStrOption { default = user; };

      # Users that get the shared-registry MCP entry
      # (programs.mcp.servers.agent-memory), consumed by opencode, claude-code
      # and prime-agent. Per-user scoping lives here — on the service owner —
      # instead of in each client.
      users = mkStrListOption { default = users; };
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
          inherit (lib) elem mkIf;

          cfg = config.icedos.applications.agent-memory;

          home = config.users.users.${cfg.user}.home;
          envFile = "${home}/${cfg.envFile}";
          stateDir = "${home}/.local/state/agent-memory";
          gatewayFile = "${stateDir}/tdai-gateway.yaml";
          mcpPatched = "${stateDir}/mcp-server.mjs";

          network = "tdai-memory-stack";
          coreName = "tdai-memory-core";
          hubName = "tdai-memory-hub";

          # In-container knowledge port. The image's entrypoint reads
          # KNOWLEDGE_PORT, and KNOWLEDGE_PUBLIC_BASE_URL must point at the same
          # value — a single binding keeps the two in lockstep (the host-side
          # cfg.knowledgePort maps onto it and is intentionally independent).
          containerKnowledgePort = "8424";

          # Neither writeShellScript nor a systemd unit provides a usable PATH.
          scriptPath = lib.makeBinPath [
            pkgs.coreutils
            pkgs.curl
            pkgs.gnugrep
            pkgs.gnused
            pkgs.podman
          ];

          # Config the core container reads. Kept as a store template with an
          # @API_KEY@ placeholder so the key never lands in the nix store; the
          # real file is rendered 0600 at unit start. Mirrors what upstream's
          # start-memory-core.sh generates.
          gatewayTemplate = pkgs.writeText "tdai-gateway.yaml.in" ''
            deployMode: standalone
            stateBackend: local

            server:
              port: 8420
              host: 0.0.0.0

            data:
              baseDir: /data/tdai-memory

            llm:
              baseUrl: "${cfg.llmBaseUrl}"
              apiKey: "@API_KEY@"
              model: "${cfg.llmModel}"
              maxTokens: 32000
              timeoutMs: 300000

            memory:
              promptMode: ${cfg.promptMode}
              capture: { enabled: true }
              extraction:
                enabled: true
                enableDedup: true
                maxMemoriesPerSession: 20
              persona:
                triggerEveryN: 50
                maxScenes: 15
              pipeline:
                everyNConversations: 5
                enableWarmup: true
                l1IdleTimeoutSeconds: 600
                l2DelayAfterL1Seconds: 90
                l2MinIntervalSeconds: 900
                l2MaxIntervalSeconds: 3600
              recall:
                enabled: true
                maxResults: 5
                scoreThreshold: 0.3
                strategy: hybrid
                timeoutMs: 5000
              storeBackend: sqlite
              embedding:
                provider: none

            skill:
              enabled: true
              routing:
                mode: bm25
                searchTopK: 20
              extraction:
                enabled: true
                maxIterations: 16
                queue:
                  backend: local
                  keyPrefix: tdai
                  resultTtlSeconds: 86400
                  lockTtlMs: 600000
                  maxRetries: 2
                  retryBackoffsMs: [5000, 15000]
              resources:
                maxResourceSizeBytes: 5000000
          '';

          # oci-containers does not create podman networks, so the shared
          # network the two containers resolve each other over is made here.
          corePre = pkgs.writeShellScript "agent-memory-core-pre" ''
            set -eu
            export PATH=${scriptPath}:$PATH

            if [ -z "''${MEMORY_LLM_API_KEY:-}" ]; then
              echo "agent-memory: MEMORY_LLM_API_KEY is unset." >&2
              echo "  Expected it in ${envFile} (mode 0600)." >&2
              exit 1
            fi

            # The file may not exist yet (the user creates it); the key check
            # above reads it via the unit's EnvironmentFile. Tighten it if there.
            chmod 600 "${envFile}" 2>/dev/null || true

            install -d -m 700 "${stateDir}"
            umask 077
            KEY_ESC=$(printf '%s' "$MEMORY_LLM_API_KEY" | sed 's/[&|\\]/\\&/g')
            sed "s|@API_KEY@|$KEY_ESC|" ${gatewayTemplate} > "${gatewayFile}"

            podman network exists ${network} || podman network create ${network}
          '';

          # sdnotify is conmon (see the container definition), so "started" does
          # not mean "serving". Blocking here makes dependsOn a real readiness
          # gate for the hub. init-admin only fires on a fresh volume.
          corePost = pkgs.writeShellScript "agent-memory-core-post" ''
            set -eu
            export PATH=${scriptPath}:$PATH

            for _ in $(seq 1 60); do
              if curl -fsS --max-time 3 \
                   "http://127.0.0.1:${toString cfg.corePort}/health" >/dev/null 2>&1; then
                break
              fi
              sleep 2
            done

            install -d -m 700 "${stateDir}"
            key_file="${stateDir}/admin-key"
            [ -s "$key_file" ] && exit 0

            umask 077
            key="sk-mem-$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)"

            resp=$(curl -sS -o /dev/null -w '%{http_code}' \
              -X POST -H 'Content-Type: application/json' \
              -H 'x-tdai-service-id: default' \
              "http://127.0.0.1:${toString cfg.corePort}/v3/internal/meta/user/init-admin" \
              -d "{\"username\":\"admin\",\"user_key\":\"$key\"}" || echo 000)

            if [ "$resp" = "200" ] || [ "$resp" = "201" ]; then
              printf '%s' "$key" > "$key_file"
              echo "agent-memory: admin user created, key saved to $key_file"
            else
              echo "agent-memory: init-admin returned HTTP $resp (admin may already exist)" >&2
            fi
          '';

          # Upstream's MCP stdio client never sends x-tdai-service-id and the
          # knowledge service rejects every request without it, with no env
          # default.
          #
          # Patching it with `podman exec` after start does NOT work here: exec
          # has to join the container's cgroup, which lives under the user
          # manager's delegated hierarchy, while this unit runs in the system
          # slice (User= is not the same as being inside user@.service). crun
          # fails with "write to .../cgroup.procs: Permission denied" and the
          # unit dies with status 126.
          #
          # So the file is extracted from the image, patched on the host, and
          # bind-mounted over the in-image path. Regenerated on every start, so
          # it tracks whatever the pinned image ships.
          hubPre = pkgs.writeShellScript "agent-memory-hub-pre" ''
            set -eu
            export PATH=${scriptPath}:$PATH

            install -d -m 700 "${stateDir}"
            tmp="${mcpPatched}.tmp"

            # Same pull policy as the container itself. Without this the
            # extraction reads the stale local image while ExecStart then pulls
            # a newer one, and we would mount an out-of-date bundle over it.
            podman run --rm --pull="${cfg.pullPolicy}" --entrypoint cat "${cfg.hubImage}" \
              /app/knowledge/dist/mcp/server.mjs > "$tmp"

            if ! grep -q x-tdai-service-id "$tmp"; then
              # Delimiter is @ on purpose: the replacement contains "||", which
              # would terminate an s|...|...| expression.
              sed -i "s@const headers = { \"Content-Type\": \"application/json\" };@const headers = { \"Content-Type\": \"application/json\", \"x-tdai-service-id\": process.env.KNOWLEDGE_SERVICE_ID || \"default\" };@" "$tmp"
            fi

            # Fail loudly rather than ship a silently broken MCP if a future
            # image no longer contains the line this patch matches.
            if ! grep -q x-tdai-service-id "$tmp"; then
              echo "agent-memory: could not patch the MCP bundle — the image no longer" >&2
              echo "  contains the expected 'const headers = { \"Content-Type\": ... };' line." >&2
              rm -f "$tmp"
              exit 1
            fi

            chmod 644 "$tmp"
            mv "$tmp" "${mcpPatched}"
          '';
        in
        mkIf cfg.service {
          # oci-containers asserts on this for rootless containers, and without
          # it the stack would only live as long as a session.
          users.users.${cfg.user}.linger = true;

          virtualisation.oci-containers.containers = {
            ${coreName} = {
              image = cfg.coreImage;
              # Rootless: a system unit with User= and HOME= pointing at this
              # user, so it uses their existing container storage and volumes.
              podman.user = cfg.user;
              # "healthy" would be better, but it asserts a statically assigned
              # uid for the user. corePost blocks on /health instead.
              podman.sdnotify = "conmon";
              pull = cfg.pullPolicy;
              networks = [ network ];
              ports = [ "127.0.0.1:${toString cfg.corePort}:8420" ];

              volumes = [
                "tdai-memory-core-data:/data/tdai-memory"
                "${gatewayFile}:/data/config/tdai-gateway.yaml:ro"
              ];

              environment = {
                TDAI_GATEWAY_PORT = "8420";
                TDAI_GATEWAY_HOST = "0.0.0.0";
                TDAI_DATA_DIR = "/data/tdai-memory";
              };

              extraOptions = [ "--network-alias=memory-core" ];
            };

            ${hubName} = {
              image = cfg.hubImage;
              podman.user = cfg.user;
              podman.sdnotify = "conmon";
              pull = cfg.pullPolicy;
              dependsOn = [ coreName ];
              networks = [ network ];

              ports = [
                "127.0.0.1:${toString cfg.panelPort}:8125"
                "127.0.0.1:${toString cfg.knowledgePort}:${containerKnowledgePort}"
              ];

              volumes = [
                "tdai-panel-data:/data/knowledge"
                "${mcpPatched}:/app/knowledge/dist/mcp/server.mjs:ro"
              ];

              # Supplies LLM_API_KEY to the container without it passing through
              # the nix store.
              environmentFiles = [ envFile ];

              environment = {
                PANEL_PORT = "8125";
                KNOWLEDGE_PORT = containerKnowledgePort;
                # Consumed INSIDE the container (it advertises its own endpoint),
                # so it must be the container-internal address — NOT the host-side
                # published port (cfg.knowledgePort). Coupling it to the host port
                # would make the URL unreachable from within whenever
                # knowledgePort ≠ 8424.
                KNOWLEDGE_PUBLIC_BASE_URL = "http://127.0.0.1:${containerKnowledgePort}/v3";
                REMOTE_INSTANCE_ID = "default";
                REMOTE_INSTANCE_NAME = "default";
                REMOTE_INSTANCE_URL = "http://memory-core:8420";
                # Required by the image's entrypoint; upstream defaults it to
                # "local". Omitting it makes the container exit immediately.
                REMOTE_INSTANCE_KEY = "local";
                LLM_MODE = "custom";
                LLM_PROTOCOL = cfg.llmProtocol;
                LLM_BASE_URL = cfg.llmBaseUrl;
                LLM_MODEL = cfg.llmModel;
                KNOWLEDGE_LLM_BINDING_SYNC = "0";
              };

              extraOptions = [
                "--network-alias=memory-hub"
                "--add-host=host.docker.internal:host-gateway"
              ];
            };
          };

          # serviceConfig list values concatenate across definitions, so these
          # append to the ExecStartPre the oci-containers module already sets
          # rather than replacing it.
          #
          # Hardening notes: NoNewPrivileges and CapabilityBoundingSet are
          # deliberately NOT set here — rootless podman relies on the setuid
          # newuidmap/newgidmap helpers to build the container's uid map, and
          # both settings break that. That also rules out every seccomp-based
          # restriction: systemd IMPLIES NoNewPrivileges=yes for a unit that
          # runs without CAP_SYS_ADMIN whenever any of RestrictAddressFamilies,
          # RestrictRealtime, RestrictSUIDSGID, ProtectKernelTunables or
          # ProtectKernelModules is set — exactly this unit (User= podman user
          # in the system slice) — so they would break newuidmap/newgidmap just
          # as surely as setting NoNewPrivileges directly. Only
          # mount-namespace-based options are safe here (PrivateTmp,
          # ProtectControlGroups — the cgroupfs read-only it imposes is fine,
          # rootless podman gets no cgroup delegation in the system slice
          # anyway). ProtectSystem is NOT set either: the strict/full variants
          # make the filesystem tree read-only, which would also cover podman's
          # own rootless storage (~/.local/share/containers) and runroot
          # ($XDG_RUNTIME_DIR/containers) — the units' ExecStart IS `podman
          # run`. ProtectHome stays false because corePre/corePost/hubPre write
          # under ${home}/.local/state. ReadWritePaths is NOT set: without
          # ProtectSystem it confines nothing, and systemd sets up the listed
          # path's mount namespace before any Exec* runs — the dir only exists
          # after corePre's `install -d` — so on a fresh machine the unit would
          # die with 226/NAMESPACE. The port exposure is instead handled by
          # binding published ports to loopback.
          systemd.services."podman-${coreName}".serviceConfig = {
            # Systemd-level, not --env-file: corePre needs the key to render the
            # gateway config before the container exists.
            EnvironmentFile = [ envFile ];
            ExecStartPre = [ "${corePre}" ];
            ExecStartPost = [ "${corePost}" ];

            PrivateTmp = true;
            ProtectHome = false;
            ProtectControlGroups = true;
            UMask = "0077";
          };

          systemd.services."podman-${hubName}".serviceConfig = {
            ExecStartPre = [ "${hubPre}" ];
            PrivateTmp = true;
            ProtectHome = false;
            ProtectControlGroups = true;
            UMask = "0077";
          };

          # Shared-registry MCP entry. Declared here — on the service owner —
          # rather than in each client, so opencode (enableMcpIntegration),
          # claude-code (claude-icedos) and prime-agent all pick the server up
          # from the one programs.mcp.servers registry instead of duplicating
          # per-client wiring. Gated on cfg.service: with service = false the
          # stack never runs, so there is nothing to exec into.
          home-manager.sharedModules = [
            (
              { config, ... }:
              lib.mkIf (elem config.home.username cfg.users) {
                programs.mcp.servers.agent-memory = {
                  # podman, not docker: the `docker` shim only exists when some
                  # other module enables virtualisation.podman.dockerCompat.
                  command = "podman";
                  args = [
                    "exec"
                    "-i"
                    # Mandatory. The image defaults to LOG_LEVEL=info and the
                    # server logs its startup lines through console.log — stdout,
                    # the same channel as JSON-RPC — which corrupts the MCP
                    # handshake.
                    "-e"
                    "LOG_LEVEL=warn"
                    # The server defaults to :8421 and appends /v3 itself, so
                    # this is the bare origin. Points at the container-internal
                    # knowledge port (containerKnowledgePort), not the published
                    # cfg.knowledgePort — the MCP server runs inside the
                    # container, so the host-side port is unreachable from there.
                    "-e"
                    "KNOWLEDGE_API_URL=http://127.0.0.1:${containerKnowledgePort}"
                    hubName
                    "node"
                    "/app/knowledge/dist/mcp/server.mjs"
                  ];
                };
              }
            )
          ];
        }
      )
    ];

  meta = {
    name = "agent-memory";

    # The container runtime is not this module's to enable. Depending on the
    # podman module keeps the stack working even if the only other consumer
    # (dtek-tools' ddev) is ever dropped.
    dependencies = [
      {
        url = "github:icedos/virtualisation";
        modules = [ "podman" ];
      }
    ];
  };
}
