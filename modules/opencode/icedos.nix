{ icedosLib, lib, ... }:

{
  options.icedos.applications.opencode =
    let
      inherit (icedosLib)
        mkAttrsOfOption
        mkNumberOption
        mkStrListOption
        mkStrOption
        ;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.applications.opencode)
        agentMemory
        extraSettings
        peonPingOverrides
        skills
        ;
    in
    {
      # Knowledge MCP server (code graph + wiki) from the apps `agent-memory`
      # module. Kept here rather than in that module so each client owns its own
      # wiring, matching how claude-icedos owns the Claude Code side.
      agentMemory = {
        users = mkStrListOption { default = agentMemory.users; };
        containerName = mkStrOption { default = agentMemory.containerName; };
        knowledgePort = mkNumberOption { default = agentMemory.knowledgePort; };
      };

      extraSettings = mkAttrsOfOption { default = extraSettings; } lib.types.anything;

      # Merged on top of the resolved peon-ping user settings when generating
      # ~/.config/opencode/peon-ping/config.json. The plugin's loadConfig()
      # reads that file and merges it over its own DEFAULT_CONFIG, so writing
      # only overrides would silently restore plugin defaults for every omitted
      # key — therefore the module writes the *full* resolved config (base
      # settings + overrides via recursiveUpdate, so every key here wins over
      # the base). Keys recognised by the adapter:
      # default_pack, active_pack, volume, enabled, desktop_notifications,
      # pack_rotation, pack_rotation_mode, path_rules, exclude_dirs, ide_rules,
      # mobile_notify, spam_threshold, spam_window_seconds, plus categories
      # (deep-merged over the base map, not replaced).
      peonPingOverrides = mkAttrsOfOption { default = peonPingOverrides; } lib.types.anything;

      skills = mkAttrsOfOption { default = skills; } lib.types.anything;
    };

  outputs.nixosModules =
    { inputs, ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (lib) elem optionalAttrs recursiveUpdate;
          inherit (config.icedos.applications.opencode)
            agentMemory
            extraSettings
            peonPingOverrides
            skills
            ;

          peonPingUsers = config.icedos.applications.peon-ping.users or { };
          peonPingEnabled = peonPingUsers != { };

          # Merged into the mcp block rather than defined as an extraSettings
          # option value, so it composes with the entries declared in
          # config/configs/opencode.toml instead of fighting them.
          agentMemoryMcpFor =
            user:
            optionalAttrs (elem user agentMemory.users) {
              mcp.agent-memory = {
                type = "local";
                enabled = true;

                command = [
                  # podman, not docker: the `docker` shim only exists when some
                  # other module enables virtualisation.podman.dockerCompat.
                  "podman"
                  "exec"
                  "-i"
                  # Mandatory. The image defaults to LOG_LEVEL=info and the server
                  # logs its startup lines through console.log — stdout, the same
                  # channel as JSON-RPC — which corrupts the MCP handshake.
                  "-e"
                  "LOG_LEVEL=warn"
                  # The server defaults to :8421 and appends /v3 itself, so this
                  # is the bare origin.
                  "-e"
                  "KNOWLEDGE_API_URL=http://127.0.0.1:${toString agentMemory.knowledgePort}"
                  agentMemory.containerName
                  "node"
                  "/app/knowledge/dist/mcp/server.mjs"
                ];
              };
            };
        in
        {
          home-manager.sharedModules = [
            (
              # Takes the home-manager config so the agent-memory entry can be
              # scoped per user, matching claude-code's per-user model. Note the
              # inner `config` shadows the NixOS one — everything read from the
              # NixOS side is captured in the outer `let`.
              { config, ... }:

              {
                programs.opencode = {
                  enable = true;

                  settings = recursiveUpdate {
                    "$schema" = "https://opencode.ai/config.json";

                    # Auto-allow skills discovered from ~/.claude/skills (Claude-compatible).
                    permission.skill."*" = "allow";
                  } (recursiveUpdate extraSettings (agentMemoryMcpFor config.home.username));

                  skills = skills;
                };
              }
            )

            (
              {
                config,
                lib,
                pkgs,
                ...
              }:

              lib.mkIf peonPingEnabled (
                let
                  userCfg = peonPingUsers.${config.home.username} or null;

                  baseSettings =
                    if userCfg != null then
                      {
                        default_pack = userCfg.defaultPack;
                        volume = userCfg.volume;
                        desktop_notifications = userCfg.desktopNotifications;
                        suppress_subagent_complete = userCfg.suppressSubagentComplete;
                        silent_window_seconds = userCfg.silentWindowSeconds;
                      }
                      // lib.optionalAttrs (userCfg.categories or { } != { }) {
                        categories = userCfg.categories;
                      }
                    else
                      { };

                  fullConfig = lib.recursiveUpdate baseSettings peonPingOverrides;
                in
                {
                  # Upstream plugin writes an OSC set-title escape to stdout with no
                  # TTY guard. Harmless in the TUI, but under Zed's ACP mode opencode's
                  # stdout is the JSON-RPC pipe, so the escape corrupts the stream and
                  # Zed hangs at "loading…". Guard the write on an interactive TTY.
                  xdg.configFile."opencode/plugins/peon-ping.ts".source =
                    pkgs.runCommand "peon-ping-opencode.ts" { }
                      ''
                        substitute ${inputs.peon-ping}/adapters/opencode/peon-ping.ts "$out" \
                          --replace-fail \
                            'process.stdout.write(`\x1b]0;' \
                            'if (process.stdout.isTTY) process.stdout.write(`\x1b]0;'
                      '';

                  xdg.configFile."opencode/peon-ping/config.json" = lib.mkIf (userCfg != null) {
                    source = (pkgs.formats.json { }).generate "opencode-peon-ping.json" fullConfig;
                  };
                }
              )
            )
          ];
        }
      )
    ];

  meta.name = "opencode";
}
