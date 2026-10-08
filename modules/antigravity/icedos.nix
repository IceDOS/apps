{ icedosLib, lib, ... }:

{
  options.icedos.applications.antigravity =
    let
      inherit (lib) importTOML;
      inherit (icedosLib)
        mkAttrsOfOption
        mkBoolOption
        ;

      inherit ((importTOML ./config.toml).icedos.applications.antigravity)
        enableMcpIntegration
        extraMcpServers
        rules
        statusLine
        statusLineStackWithDefault
        ;
    in
    {
      # Whether to wire Home Manager's shared programs.mcp.servers registry
      # into ~/.gemini/config/mcp_config.json for Antigravity.
      enableMcpIntegration = mkBoolOption { default = enableMcpIntegration; };

      # Additional MCP servers registered exclusively for Antigravity.
      extraMcpServers = mkAttrsOfOption { default = extraMcpServers; } lib.types.anything;

      # Global rules, written to ~/.gemini/config/rules/<name>.md (agy reads that folder's top level only).
      rules = mkAttrsOfOption { default = rules; } lib.types.lines;

      # Antigravity CLI bottom status bar (/statusline); configured via agy's own settings.json.
      statusLine = mkBoolOption { default = statusLine; };

      # Render the bar below agy's built-in header instead of replacing it.
      statusLineStackWithDefault = mkBoolOption { default = statusLineStackWithDefault; };
    };

  outputs.nixosModules =
    { repoUrl, ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          icedosLib,
          ...
        }:

        let
          inherit (config.icedos.applications.antigravity)
            enableMcpIntegration
            extraMcpServers
            rules
            statusLine
            statusLineStackWithDefault
            ;
          inherit (lib)
            filterAttrs
            hasPrefix
            mapAttrs
            mapAttrs'
            mkIf
            nameValuePair
            optionalAttrs
            ;

          jsonFormat = pkgs.formats.json { };

          # agy drops a rules/*.md file without a trigger, so plain text becomes always_on.
          withTrigger =
            text: if hasPrefix "---\n" text then text else "---\ntrigger: always_on\n---\n\n${text}";

          # Wrapper so activation and settings.json share one store path.
          statusLinePkg = pkgs.writeShellApplication {
            name = "antigravity-statusline";
            text = ''
              exec ${pkgs.python3}/bin/python3 ${./statusline.py} "$@"
            '';
          };

          hasZed = icedosLib.hasModule {
            inherit config repoUrl;
            name = "zed";
          };
        in
        {
          icedos.applications = lib.optionalAttrs hasZed {
            zed.agentBridge.agents.antigravity = {
              command = lib.mkDefault [ "agy" ];
              resumeArgs = lib.mkDefault [
                "--conversation"
                "{id}"
              ];
              locator = lib.mkDefault "antigravity";
              label = lib.mkDefault "Antigravity CLI";
            };
          };

          home-manager.sharedModules = [
            (
              { config, lib, ... }:

              let
                # Pull every server from the shared programs.mcp.servers registry
                mcpRegistry =
                  if enableMcpIntegration && (config.programs.mcp.enable or false) then
                    config.programs.mcp.servers or { }
                  else
                    { };

                allServers = mcpRegistry // extraMcpServers;

                isEnabled =
                  s:
                  if (s.enabled or null) != null then
                    s.enabled
                  else if (s.disabled or null) != null then
                    !s.disabled
                  else
                    true;

                enabledServers = filterAttrs (_: isEnabled) allServers;

                transformServer =
                  s:
                  if (s.command or null) != null then
                    {
                      inherit (s) command;
                    }
                    // optionalAttrs ((s.args or [ ]) != [ ]) { inherit (s) args; }
                    // optionalAttrs ((s.env or { }) != { }) {
                      env = mapAttrs (_: v: if builtins.isAttrs v && v ? file then v.file else v) s.env;
                    }
                  else if (s.url or null) != null then
                    {
                      serverUrl = s.url;
                    }
                    // optionalAttrs ((s.headers or { }) != { }) { inherit (s) headers; }
                  else if (s.serverUrl or null) != null then
                    {
                      inherit (s) serverUrl;
                    }
                  else
                    s;

                mcpConfig = {
                  mcpServers = mapAttrs (_: transformServer) enabledServers;
                };
              in
              {
                home.file = {
                  ".gemini/config/mcp_config.json" = mkIf (enabledServers != { }) {
                    source = jsonFormat.generate "antigravity-mcp-config.json" mcpConfig;
                  };
                }
                // mapAttrs' (
                  name: text: nameValuePair ".gemini/config/rules/${name}.md" { text = withTrigger text; }
                ) rules;

                # agy owns ~/.gemini/antigravity-cli/settings.json (it writes on settings
                # changes), so Home Manager only merges/removes its statusLine key.
                home.activation.icedosAntigravityStatusLine = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                  run ${statusLinePkg}/bin/antigravity-statusline --setup ${
                    if statusLine then "on" else "off"
                  } ${lib.escapeShellArg "${statusLinePkg}/bin/antigravity-statusline"}${lib.optionalString statusLineStackWithDefault " --stack"}
                '';
              }
            )
          ];

          icedos.system.tips.list = [
            "Antigravity automatically discovers MCP servers declared in programs.mcp.servers."
          ];
        }
      )
    ];

  meta.name = "antigravity";
}
