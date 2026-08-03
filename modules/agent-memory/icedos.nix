{ icedosLib, lib, ... }:

{
  options.icedos.applications.agent-memory =
    let
      inherit (lib) importTOML;

      inherit (icedosLib)
        mkBoolOption
        mkNumberOption
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
          inherit (lib) mkIf;

          cfg = config.icedos.applications.agent-memory;

          home = config.users.users.${cfg.user}.home;
          envFile = "${home}/${cfg.envFile}";
          stateDir = "${home}/.local/state/agent-memory";
          gatewayFile = "${stateDir}/tdai-gateway.yaml";
          mcpPatched = "${stateDir}/mcp-server.mjs";

          network = "tdai-memory-stack";
          coreName = "tdai-memory-core";
          hubName = "tdai-memory-hub";

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

            install -d -m 700 "${stateDir}"
            umask 077
            sed "s|@API_KEY@|$MEMORY_LLM_API_KEY|" ${gatewayTemplate} > "${gatewayFile}"

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

            install -d -m 755 "${stateDir}"
            tmp="${mcpPatched}.tmp"

            # Same pull policy as the container itself. Without this the
            # extraction reads the stale local image while ExecStart then pulls
            # a newer one, and we would mount an out-of-date bundle over it.
            podman run --rm --pull=${cfg.pullPolicy} --entrypoint cat ${cfg.hubImage} \
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
              ports = [ "${toString cfg.corePort}:8420" ];

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
                "${toString cfg.panelPort}:8125"
                "${toString cfg.knowledgePort}:8424"
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
                KNOWLEDGE_PORT = "8424";
                KNOWLEDGE_PUBLIC_BASE_URL = "http://host.docker.internal:${toString cfg.knowledgePort}/v3";
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
          systemd.services."podman-${coreName}".serviceConfig = {
            # Systemd-level, not --env-file: corePre needs the key to render the
            # gateway config before the container exists.
            EnvironmentFile = [ envFile ];
            ExecStartPre = [ "${corePre}" ];
            ExecStartPost = [ "${corePost}" ];
          };

          systemd.services."podman-${hubName}".serviceConfig.ExecStartPre = [ "${hubPre}" ];
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
