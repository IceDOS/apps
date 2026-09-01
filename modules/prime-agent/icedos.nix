{ icedosLib, lib, ... }:

{
  options.icedos.applications.prime-agent =
    let
      inherit (lib) importTOML types;

      inherit (icedosLib)
        mkAttrsOfOption
        mkBoolOption
        mkIntBetweenOption
        mkStrListOption
        mkStrOption
        mkSubmoduleAttrsOption
        ;

      inherit ((importTOML ./config.toml).icedos.applications.prime-agent)
        costFooter
        dataDir
        defaultModel
        defaultProvider
        keybind
        mcpCallTimeout
        portBase
        portOverrides
        builtinExtensions
        extensions
        includeInIcedosGc
        sessionRetentionDays
        providers
        skillDirs
        shareTraces
        telemetry
        ;
    in
    {
      defaultProvider = mkStrOption { default = defaultProvider; };
      defaultModel = mkStrOption { default = defaultModel; };

      # Zed keybind to spawn prime-agent (Ctrl-Alt-P default).
      keybind = mkStrOption { default = keybind; };

      dataDir = mkStrOption { default = dataDir; };

      # Whether `icedos gc` prunes stale prime-agent sessions (unshade-style).
      includeInIcedosGc = mkBoolOption { default = includeInIcedosGc; };

      # Sessions/logs older than this many days are pruned by the GC hook.
      sessionRetentionDays = mkIntBetweenOption {
        path = "icedos.applications.prime-agent.sessionRetentionDays";
        source = ./config.toml;
        default = sessionRetentionDays;
      } 1 3650;

      mcpCallTimeout = mkIntBetweenOption {
        path = "icedos.applications.prime-agent.mcpCallTimeout";
        source = ./config.toml;
        default = mcpCallTimeout;
      } 60 3600;

      # Install the cost-footer extension: live session cost (USD) in the TUI bottom bar.
      costFooter = mkBoolOption { default = costFooter; };

      # Upload full session traces (transcripts, cwd, git repo/commit) to Prime
      # Intellect to train open-source LLMs. Off by default; /traces on toggles it.
      shareTraces = mkBoolOption { default = shareTraces; };

      # Send product analytics (token usage, model/provider categories) to Prime
      # Intellect. Off by default (flips upstream's telemetry.enabled = true).
      telemetry = mkBoolOption { default = telemetry; };

      skillDirs = mkStrListOption { default = skillDirs; };

      # Built-in example extensions to load (names under examples/extensions/).
      builtinExtensions = mkStrListOption { default = builtinExtensions; };

      # Inline .ts sources for auto-loaded local extensions (like Claude skills).
      extensions = mkAttrsOfOption { default = extensions; } types.str;

      # Bound is 65335 so portBase + (sha256(name) mod 200) stays <= 65535.
      portBase = mkIntBetweenOption {
        path = "icedos.applications.prime-agent.portBase";
        source = ./config.toml;
        default = portBase;
      } 0 65335;

      # Pins are system-wide; derived ports fold the username in and cannot collide.
      portOverrides = mkAttrsOfOption { default = portOverrides; } (lib.types.ints.between 1 65535);

      # Provider overrides merged into models.json (modelOverrides is partial merge).
      providers = mkSubmoduleAttrsOption { default = providers; } {
        apiKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "API key for the provider. null = hardcoded default.";
        };

        baseUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Base URL for the provider API.";
        };

        headers = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Extra HTTP headers for provider requests.";
        };

        modelOverrides = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                contextWindow = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = null;
                  description = "Context window size in tokens.";
                };

                maxTokens = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = null;
                  description = "Max output tokens per response.";
                };

                name = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Model display name.";
                };

                reasoning = lib.mkOption {
                  type = lib.types.nullOr lib.types.bool;
                  default = null;
                  description = "Whether the model supports reasoning.";
                };
              };
            }
          );

          default = { };
          description = "Per-model overrides keyed by model id.";
        };

        # Custom model definitions emitted into models.json "models". A model whose
        # id the bundled catalog lacks is ADDED (inheriting the provider's built-in
        # api/baseUrl); an id that already exists replaces the bundled definition.
        models = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                id = lib.mkOption {
                  type = lib.types.str;
                  description = "Model id (also the key used in modelOverrides).";
                };

                name = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Model display name.";
                };

                reasoning = lib.mkOption {
                  type = lib.types.nullOr lib.types.bool;
                  default = null;
                  description = "Whether the model supports reasoning.";
                };

                contextWindow = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = null;
                  description = "Context window size in tokens.";
                };

                maxTokens = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = null;
                  description = "Max output tokens per response.";
                };

                input = lib.mkOption {
                  type = lib.types.listOf (
                    lib.types.enum [
                      "text"
                      "image"
                    ]
                  );
                  default = [ ];
                  description = "Input modalities the model accepts.";
                };

                cost = lib.mkOption {
                  type = lib.types.nullOr (lib.types.attrsOf lib.types.number);
                  default = null;
                  description = "Per-token cost (USD per 1M tokens). prime-agent requires input, output, cacheRead, cacheWrite.";
                };

                api = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "API protocol; defaults to the provider's built-in api.";
                };

                baseUrl = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "API base URL; defaults to the provider's built-in baseUrl.";
                };
              };
            }
          );

          default = [ ];
          description = "Custom model definitions for providers. Adds a model the bundled catalog lacks (e.g. a newly released one) so it appears in the model list without rebuilding the package.";
        };
      };

      users = mkSubmoduleAttrsOption { default = { }; } { };
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
          inherit (lib)
            concatMapStrings
            concatStrings
            concatStringsSep
            mapAttrs'
            mkIf
            mkMerge
            nameValuePair
            replaceStrings
            splitString
            stringToCharacters
            substring
            toUpper
            ;

          inherit (config.icedos.applications) prime-agent;
          primeAgentUsers = prime-agent.users;
          # peon-ping is a standalone module and may not be loaded at all.
          peonPingEnabled = (config.icedos.applications.peon-ping.users or { }) != { };

          # Prune stale prime-agent session data during `icedos gc`.
          primeAgentGcHook = ''
            D='${prime-agent.dataDir}'
            # Matches config.xdg.configHome default ($HOME/.config); env -i strips
            # per-user xdg, so non-default paths go through the dataDir option.
            [ -z "$D" ] && D='$HOME/.config/prime-agent'
            # Expand XDG/tilde refs under the minimal gc env (HOME-only).
            D=''${D/\$XDG_CONFIG_HOME/$HOME/.config}
            D=''${D/\$XDG_DATA_HOME/$HOME/.local/share}
            D=''${D/#~/\$HOME}
            D=''${D//\$HOME/$HOME}
            [ -d "''${D}" ] || { log_warn "prime-agent gc: data dir ''${D} not found; skipping"; exit 0; }
            find "''${D}/sessions" -maxdepth 1 -type f -name '*.jsonl' -mtime "+${toString prime-agent.sessionRetentionDays}" -delete 2>/dev/null || true
            for a in "''${D}"/session-artifacts/*; do
              [ -d "$a" ] || continue
              [ -f "''${D}/sessions/$(basename "$a").jsonl" ] && continue
              [ -n "$(find "$a" -prune -mtime "+${toString prime-agent.sessionRetentionDays}" -print)" ] && rm -rf -- "$a"
            done
            find "''${D}/logs" -maxdepth 1 -type f -mtime "+${toString prime-agent.sessionRetentionDays}" -delete 2>/dev/null || true
          '';
        in
        {
          # Copy of nixpkgs PR #550774 at 0.7.4; drop overlay, package.nix and patch once merged.
          nixpkgs.overlays = [
            (final: _prev: {
              prime-agent = final.callPackage ./package.nix {
                mcpCallTimeout = prime-agent.mcpCallTimeout;
              };
            })
          ];

          environment.systemPackages = [ pkgs.prime-agent ];

          icedos.applications.prime-agent.users = icedosLib.users.genDefaults {
            inherit (config.icedos) users;
          };

          # `icedos gc` prunes stale prime-agent sessions per user (unshade-style).
          icedos.system.gc.hooks.postGc = mkIf prime-agent.includeInIcedosGc [
            primeAgentGcHook
          ];

          # Same TUI the Zed task spawns, as a toolset leaf so `icedos <tool>` stays uniform.
          icedos.system.toolset.commands = lib.mkIf (primeAgentUsers != { }) [
            {
              command = "prime-agent";
              bin = "${pkgs.prime-agent}/bin/prime-agent";
              help = "prime-agent AI assistant (interactive session)";
            }
          ];

          home-manager.sharedModules = [
            (
              {
                config,
                lib,
                pkgs,
                ...
              }:

              let
                userCfg = primeAgentUsers.${config.home.username} or null;
                # ---- data dir ----
                # "" means the default; expanded per user here (prime-agent knows ~, not $VARS).
                dataDir =
                  let
                    raw = if prime-agent.dataDir == "" then "$XDG_CONFIG_HOME/prime-agent" else prime-agent.dataDir;

                    expand =
                      builtins.replaceStrings
                        [
                          "$XDG_CONFIG_HOME"
                          "$XDG_DATA_HOME"
                          "$HOME"
                        ]
                        [
                          config.xdg.configHome
                          config.xdg.dataHome
                          config.home.homeDirectory
                        ]
                        raw;
                    # "$HOME/" must hit the rejected "$HOME" case, not a leading-slash relDataDir.
                    stripped =
                      let
                        stripTrailing =
                          s: if s != "/" && lib.hasSuffix "/" s then stripTrailing (lib.removeSuffix "/" s) else s;
                      in
                      stripTrailing expand;
                    # Collapse repeated slashes; they would yield a leading-slash relDataDir.
                    collapse =
                      s:
                      let
                        s' = builtins.replaceStrings [ "//" ] [ "/" ] s;
                      in
                      if s' == s then s else collapse s';
                  in
                  collapse (
                    if stripped == "~" then
                      config.home.homeDirectory
                    else if lib.hasPrefix "~/" stripped then
                      config.home.homeDirectory + lib.removePrefix "~" stripped
                    else
                      stripped
                  );
                # home.file keys are $HOME-relative; only in-home dataDirs work (asserted below).
                relDataDir = lib.removePrefix (config.home.homeDirectory + "/") dataDir;
                # ---- shared MCP registry ----
                # Also consumed by opencode; gated on programs.mcp.enable, where hm validates it.
                registry = if config.programs.mcp.enable or false then config.programs.mcp.servers or { } else { };
                # enabled/disabled both disable; home-manager's resolver is unexported, so mirror it.
                isEnabled =
                  s:
                  if (s.enabled or null) != null then
                    s.enabled
                  else if (s.disabled or null) != null then
                    !s.disabled
                  else
                    true;

                enabled = lib.filterAttrs (_: isEnabled) registry;

                localServers = lib.filterAttrs (_: s: s.command != null) enabled;
                # ---- deterministic per-server ports ----
                # portBase + sha256(name) mod 200, collisions bumped; portOverrides wins.

                hexDigit =
                  c:
                  {
                    "0" = 0;
                    "1" = 1;
                    "2" = 2;
                    "3" = 3;
                    "4" = 4;
                    "5" = 5;
                    "6" = 6;
                    "7" = 7;
                    "8" = 8;
                    "9" = 9;
                    "a" = 10;
                    "b" = 11;
                    "c" = 12;
                    "d" = 13;
                    "e" = 14;
                    "f" = 15;
                  }
                  .${c};

                hashInt = hex: lib.foldl' (acc: c: acc * 16 + hexDigit c) 0 (stringToCharacters hex);

                # Nix has no integer modulo operator; fold modulo by hand.
                mod = a: b: a - b * (a / b);
                # Username folded in so two users' bridges cannot collide; pins stay system-wide.
                hashPort =
                  name:
                  prime-agent.portBase
                  + mod (hashInt (
                    substring 0 6 (builtins.hashString "sha256" "${config.home.username}:${name}")
                  )) 200;

                portsByServer =
                  let
                    sorted = lib.sort (a: b: a.name < b.name) (
                      lib.mapAttrsToList (name: s: s // { inherit name; }) localServers
                    );
                    # Reserved up front so derived ports bump around pins; double pins fail below.
                    pinnedUsed = lib.listToAttrs (
                      map (p: lib.nameValuePair (toString p) true) (lib.attrValues prime-agent.portOverrides)
                    );

                    step =
                      { ports, used }:
                      s:
                      let
                        find = n: if used.${toString n} or false then find (n + 1) else n;
                        p =
                          if prime-agent.portOverrides ? ${s.name} then
                            prime-agent.portOverrides.${s.name}
                          else
                            find (hashPort s.name);
                      in
                      {
                        ports = ports // {
                          ${s.name} = p;
                        };
                        used = used // {
                          ${toString p} = true;
                        };
                      };
                  in
                  (lib.foldl' step {
                    ports = { };
                    used = pinnedUsed;
                  } sorted).ports;

                # Shared final ports; empty unless the config is wrong, asserted below.
                duplicatePorts =
                  let
                    entries = lib.mapAttrsToList (name: p: { inherit name p; }) portsByServer;
                  in
                  lib.filter (e: 1 < lib.length (lib.filter (o: o.p == e.p) entries)) entries;

                portFor = name: portsByServer.${name};

                urlFor =
                  name: s: if s.command != null then "http://127.0.0.1:${toString (portFor name)}/mcp" else s.url;

                # Via home-manager's transform so freeform keys survive; prime-agent only speaks HTTP.
                mcpServers = lib.mapAttrs (
                  name: s:
                  lib.hm.mcp.transformMcpServer {
                    server = s;
                    exclude = [
                      "args"
                      "command"
                      "enabled"
                      "env"
                    ];
                    extraTransforms = [
                      (
                        srv:
                        srv
                        // {
                          type = "http";
                          url = urlFor name srv;
                        }
                      )
                    ];
                  }
                ) enabled;

                # Local bridges accept any token; remotes get none, as they can reject the header.
                dummyCreds = mapAttrs' (
                  name: _:
                  nameValuePair "mcp:${name}" {
                    type = "api_key";
                    key = "dummy";
                  }
                ) localServers;

                remoteServers = lib.filterAttrs (_: s: s.command == null) enabled;

                # Named so the seed script can retract exactly the dummies it once wrote.
                remoteCredKeysFile = pkgs.writeText "prime-agent-remote-cred-keys.json" (
                  builtins.toJSON (map (name: "mcp:${name}") (lib.attrNames remoteServers))
                );

                isNoAuthRemote =
                  s: s.command == null && (s.bearerTokenEnvVar or null) == null && !(s.oauth or false);

                # Seed-wins merge, so empty values would reset TUI choices; mcpServers always rides along.
                seedSettings =
                  (lib.optionalAttrs (prime-agent.defaultProvider != "") {
                    defaultProvider = prime-agent.defaultProvider;
                  })
                  // (lib.optionalAttrs (prime-agent.defaultModel != "") {
                    defaultModel = prime-agent.defaultModel;
                  })
                  // (lib.optionalAttrs (prime-agent.skillDirs != [ ]) {
                    skills = prime-agent.skillDirs;
                  })
                  // {
                    mcpServers = mcpServers;
                    # Deterministic even at the upstream default (agentTraces off).
                    agentTraces.enabled = prime-agent.shareTraces;
                    # Upstream defaults this to true; expose it so a user can flip it on.
                    telemetry.enabled = prime-agent.telemetry;
                  };

                # ---- per-server skill files ----
                importName = name: replaceStrings [ "-" ] [ "_" ] name;

                className =
                  name: concatStrings (map (p: toUpper (substring 0 1 p) + substring 1 99 p) (splitString "-" name));

                skillMd = name: ''
                  ---
                  name: ${name}
                  description: ${name} MCP integration — import ${importName name} in the kernel and call its tools over the local prime-agent MCP bridge.
                  ---

                  # ${name} MCP integration

                  The ${name} server is exposed as a Python-backed skill so the kernel can
                  call it over MCP. Import the module and discover tools before calling:

                  ```python
                  import ${importName name}

                  for tool in await ${importName name}.list_tools():
                      print(tool["name"], "-", tool["description"])

                  result = await ${importName name}.call_tool("<tool_name>", {...})
                  ```

                  - Every tool is an `async` method — always `await`.
                  - Results are already-parsed Python (dict / str / list of content blocks).
                  - A tool whose name isn't a valid Python identifier is called via the
                    escape hatch: `await ${importName name}.call_tool("tool-name", {...})`.
                  - If a call fails to connect, the local MCP service may be down:
                    `systemctl --user status prime-agent-${name}`.
                '';

                pyproject = name: ''
                  [project]
                  name = "prime-agent-skill-${name}"
                  version = "0.1.0"
                  requires-python = ">=3.10"
                  dependencies = ["mcp", "httpx", "prime-agent-runtime"]

                  [build-system]
                  requires = ["hatchling"]
                  build-backend = "hatchling.build"

                  [tool.hatch.build.targets.wheel]
                  packages = ["src/${importName name}"]
                '';

                pyStr = s: "\"" + replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] s + "\"";

                pyDict =
                  attrs:
                  "{" + concatStringsSep ", " (lib.mapAttrsToList (k: v: "${pyStr k}: ${pyStr v}") attrs) + "}";

                # Nix strips the block's common indent, dropping this method to column 0.
                indentPy =
                  block:
                  concatStringsSep "\n" (
                    map (line: if line == "" then "" else "    " + line) (splitString "\n" block)
                  );

                # _open_session always sends Authorization; a keyless endpoint may reject it.
                noAuthSession = ''
                  async def _open_session(self, stack):
                      import inspect

                      from mcp import ClientSession

                      try:
                          from rlm.mcp_base import _resolve_streamable_http
                      except ImportError as exc:
                          raise RuntimeError(
                              "rlm.mcp_base._resolve_streamable_http is gone; the no-auth MCP "
                              "override generated by the IceDOS prime-agent module needs updating"
                          ) from exc

                      url, headers = await self._resolve_config()
                      if not url:
                          raise ValueError(f"{type(self).__name__} has no url")
                      transport = _resolve_streamable_http()
                      params = inspect.signature(transport).parameters
                      if "headers" in params:
                          cm = transport(url, headers=headers)
                      elif "http_client" in params:
                          import httpx

                          client = await stack.enter_async_context(httpx.AsyncClient(headers=headers))
                          cm = transport(url, http_client=client)
                      else:
                          raise RuntimeError(f"unsupported streamable-HTTP signature: {tuple(params)}")
                      read, write, *_ = await stack.enter_async_context(cm)
                      session = await stack.enter_async_context(ClientSession(read, write))
                      await session.initialize()
                      return session'';

                initPy =
                  name: s: url:
                  let
                    body = [
                      "    server = ${pyStr name}"
                      "    url = ${pyStr url}"
                    ]
                    # A remote server may need headers to answer at all.
                    ++ lib.optional (s.headers or { } != { }) "    headers = ${pyDict s.headers}"
                    # _token() checks bearer_token_env before auth.json; these skip the cred seed.
                    ++ lib.optional (
                      (s.bearerTokenEnvVar or null) != null
                    ) "    bearer_token_env = ${pyStr s.bearerTokenEnvVar}"
                    ++ lib.optional (isNoAuthRemote s) (indentPy noAuthSession);
                  in
                  ''
                    from rlm import McpIntegration


                    class ${className name}(McpIntegration):
                    ${concatStringsSep "\n" body}


                    ${importName name} = ${className name}()

                    _RESERVED = {"run", "__wrapped__", "__call__"}


                    def __getattr__(name):
                        if name.startswith("_") or name in _RESERVED:
                            raise AttributeError(name)
                        return getattr(${importName name}, name)
                  '';

                skillFiles = name: s: {
                  "${relDataDir}/skills/${name}/SKILL.md".text = skillMd name;
                  "${relDataDir}/skills/${name}/pyproject.toml".text = pyproject name;
                  "${relDataDir}/skills/${name}/src/${importName name}/__init__.py".text = initPy name s (
                    urlFor name s
                  );
                };

                # ---- systemd user services (local servers) ----

                # ExecStart is one line: quote each argv element, `$` as `$$` for the inner shell.
                quoteSystemdArg =
                  arg:
                  "\""
                  + concatMapStrings (
                    c:
                    if c == "\\" then
                      "\\\\"
                    else if c == "\"" then
                      "\\\""
                    else if c == "$" then
                      "$$"
                    else
                      c
                  ) (stringToCharacters arg)
                  + "\"";
                # Environment= does not expand `$`, and reads `%` as a specifier, so double it.
                quoteSystemdEnv =
                  arg:
                  "\""
                  + concatMapStrings (
                    c:
                    if c == "\\" then
                      "\\\\"
                    else if c == "\"" then
                      "\\\""
                    else if c == "%" then
                      "%%"
                    else
                      c
                  ) (stringToCharacters arg)
                  + "\"";
                # env may hold secret file refs; hm wraps those, leaving literals for Environment=.
                withEnvFiles = name: s: lib.hm.mcp.wrapEnvFilesCommand { inherit pkgs name; } s;
                # --pass-environment is required: unlike supergateway's `sh -c`, the child gets no env.
                mcpProxy = "${pkgs.mcp-proxy}/bin/mcp-proxy";

                execStart =
                  name: s:
                  let
                    wrapped = withEnvFiles name s;
                  in
                  concatStringsSep " " (
                    map quoteSystemdArg (
                      [
                        mcpProxy
                        "--host"
                        "127.0.0.1"
                        "--port"
                        (toString (portFor name))
                        "--pass-environment"
                        "--"
                        wrapped.command
                      ]
                      ++ (wrapped.args or [ ])
                    )
                  );

                service =
                  name: s:
                  let
                    # Literal env only; file refs were consumed by the wrapper.
                    literalEnv = (withEnvFiles name s).env or { };
                  in
                  {
                    "prime-agent-${name}" = {
                      Unit = {
                        Description = "prime-agent ${name} MCP server";
                        After = [ "network.target" ];
                      };
                      Service = {
                        ExecStart = execStart name s;
                        Environment = [
                          # Don't depend on whatever PATH the user manager inherited.
                          (quoteSystemdEnv "PATH=${
                            concatStringsSep ":" [
                              "/run/current-system/sw/bin"
                              "${pkgs.nix}/bin"
                              "${config.home.profileDirectory}/bin"
                            ]
                          }")
                        ]
                        ++ lib.mapAttrsToList (k: v: quoteSystemdEnv "${k}=${v}") literalEnv;
                        Restart = "on-failure";
                        RestartSec = 5;
                      };
                      Install.WantedBy = [ "default.target" ];
                    };
                  };

                # ---- models.json ----
                # zen 429s unless identified as an opencode client.
                opencodeVersion = config.programs.opencode.package.version or pkgs.opencode.version;

                providerDefaults = {
                  opencode = {
                    headers = {
                      "User-Agent" = "opencode/${opencodeVersion}";
                    };

                    apiKey = "!node -p 'JSON.parse(require(\"fs\").readFileSync(process.env.HOME + \"/.local/share/opencode/auth.json\", \"utf8\")).opencode.key'";
                  };
                };

                # modelOverrides stays as-is for partial merge; models[] merges in
                # custom models (adds unknown ids, replaces known ones).
                userProvidersConverted = lib.mapAttrs (
                  name: p:
                  let
                    attrs = lib.filterAttrs (_: v: v != null) {
                      inherit (p) apiKey baseUrl headers;
                    };
                    overrides = lib.mapAttrs (_: o: lib.filterAttrs (_: v: v != null) o) (p.modelOverrides or { });
                    models = map (m: lib.filterAttrs (_: v: v != null) m) (p.models or [ ]);
                  in
                  attrs
                  // lib.optionalAttrs (overrides != { }) { modelOverrides = overrides; }
                  // lib.optionalAttrs (models != [ ]) { models = models; }
                ) prime-agent.providers;

                mergedProviders = lib.recursiveUpdate providerDefaults userProvidersConverted;

                modelsJson = builtins.toJSON { providers = mergedProviders; };

                modelsFile = pkgs.writeText "prime-agent-models.json" modelsJson;
                # ---- first-run seed ----
                # Idempotent: never clobbers state prime-agent writes itself.

                seedSettingsFile = pkgs.writeText "prime-agent-settings.json" (builtins.toJSON seedSettings);
                dummyCredsFile = pkgs.writeText "prime-agent-auth-seed.json" (builtins.toJSON dummyCreds);
                # `install` not `cp` (cp copies the store read-only mode), `+` not `*` for
                # auth.json (`*` recurses into credentials), `--slurpfile` (jq 1.8 dropped --argfile).
                seedScript = ''
                  JQ=${pkgs.jq}/bin/jq
                  SYNC=${pkgs.coreutils}/bin/sync
                  DATE=${pkgs.coreutils}/bin/date

                  # jq's `*` errors on a null lhs, so one empty or truncated state file would
                  # fail every later activation and stay broken. Treat unreadable state as absent.
                  json_ok() { [ -s "$1" ] && "$JQ" -e . "$1" >/dev/null 2>&1; }

                  # `> tmp && mv` alone is not crash-safe under delayed allocation (xfs, ext4):
                  # an unclean shutdown leaves a 0-byte file. fsync the tmp before the rename.
                  # Mode is set explicitly: the tmp inherits the umask, and mv carries it over.
                  commit_json() { chmod "$3" "$1" && "$SYNC" -d "$1" && mv "$1" "$2"; }

                  mkdir -p "${dataDir}"

                  SETTINGS="${dataDir}/settings.json"
                  if json_ok "$SETTINGS"; then
                    "$JQ" -n --slurpfile a "$SETTINGS" --slurpfile b "${seedSettingsFile}" '$a[0] * $b[0]' > "$SETTINGS.tmp" && commit_json "$SETTINGS.tmp" "$SETTINGS" 0644 || { rm -f "$SETTINGS.tmp"; echo "prime-agent: failed to merge $SETTINGS, left unchanged" >&2; }
                  else
                    [ -e "$SETTINGS" ] && echo "prime-agent: $SETTINGS unreadable, reseeding" >&2
                    rm -f "$SETTINGS.tmp"
                    install -m 0644 "${seedSettingsFile}" "$SETTINGS"
                  fi

                  MODELS="${dataDir}/models.json"
                  if json_ok "$MODELS"; then
                    "$JQ" -n --slurpfile a "$MODELS" --slurpfile b "${modelsFile}" '$a[0] * $b[0]' > "$MODELS.tmp" && commit_json "$MODELS.tmp" "$MODELS" 0644 || { rm -f "$MODELS.tmp"; echo "prime-agent: failed to merge $MODELS, left unchanged" >&2; }
                  else
                    [ -e "$MODELS" ] && echo "prime-agent: $MODELS unreadable, reseeding" >&2
                    rm -f "$MODELS.tmp"
                    install -m 0644 "${modelsFile}" "$MODELS"
                  fi

                  AUTH="${dataDir}/auth.json"
                  # auth.json holds real credentials, so a corrupt one is moved aside, never merged over.
                  if ! json_ok "$AUTH"; then
                    if [ -e "$AUTH" ]; then
                      mv "$AUTH" "$AUTH.corrupt.$("$DATE" +%s)"
                      echo "prime-agent: $AUTH was unreadable, moved aside; re-run /login" >&2
                    fi
                    rm -f "$AUTH.tmp"
                    # 0600 from the start; prime-agent writes it 0600 and it holds credentials.
                    printf '%s\n' '{}' > "$AUTH" && chmod 0600 "$AUTH"
                  fi
                  "$JQ" -n --slurpfile a "$AUTH" --slurpfile b "${dummyCredsFile}" '$a[0] + $b[0]' > "$AUTH.tmp" && commit_json "$AUTH.tmp" "$AUTH" 0600 || { rm -f "$AUTH.tmp"; echo "prime-agent: failed to seed MCP credentials into $AUTH" >&2; }
                  # Retract a dummy we seeded, but only if the entry is still exactly ours.
                  "$JQ" -n --slurpfile a "$AUTH" --slurpfile k "${remoteCredKeysFile}" 'reduce $k[0][] as $key ($a[0]; if .[$key] == {"type":"api_key","key":"dummy"} then del(.[$key]) else . end)' > "$AUTH.tmp" && commit_json "$AUTH.tmp" "$AUTH" 0600 || { rm -f "$AUTH.tmp"; echo "prime-agent: failed to retract seeded MCP credentials from $AUTH" >&2; }
                '';

                primeEnv = {
                  PRIME_AGENT_CODING_AGENT_DIR = dataDir;
                  PRIME_AGENT_KERNEL_VENV = "${dataDir}/kernel-venv";
                };

                # Mirror requested built-in examples into the auto-load dir.
                upstreamExtDir = "${pkgs.prime-agent}/lib/prime-agent/examples/extensions";

                # Resolve each name to its file (.ts) or folder (index.ts) source; null if absent.
                builtinExtSrc =
                  name:
                  if builtins.pathExists "${upstreamExtDir}/${name}/index.ts" then
                    {
                      src = "${upstreamExtDir}/${name}";
                      target = "${relDataDir}/extensions/${name}";
                    }
                  else if builtins.pathExists "${upstreamExtDir}/${name}.ts" then
                    {
                      src = "${upstreamExtDir}/${name}.ts";
                      target = "${relDataDir}/extensions/${name}.ts";
                    }
                  else
                    null;

                extensionHomeFiles = map (name: {
                  "${(builtinExtSrc name).target}".source = (builtinExtSrc name).src;
                }) prime-agent.builtinExtensions;

                missingExtensions = lib.filter (n: builtinExtSrc n == null) prime-agent.builtinExtensions;

                extensionLocalHomeFiles = lib.mapAttrsToList (name: src: {
                  "${relDataDir}/extensions/${name}.ts".text = src;
                }) prime-agent.extensions;
              in
              mkIf (userCfg != null) {
                assertions = [
                  {
                    assertion = lib.hasPrefix (config.home.homeDirectory + "/") dataDir && relDataDir != "";
                    message = ''
                      icedos.applications.prime-agent.dataDir must expand to a
                      path inside the home directory so the MCP skill files can
                      be installed via home.file (got "${dataDir}" from
                      "${prime-agent.dataDir}"). Use an in-home path, e.g.
                      "$XDG_CONFIG_HOME/prime-agent".
                    '';
                  }
                  # A pin is only validated by the user that enables the server; another
                  # user's pin is checked in that user's own sharedModule.
                  {
                    assertion = lib.all (n: !(enabled ? ${n}) || localServers ? ${n}) (
                      lib.attrNames prime-agent.portOverrides
                    );
                    message = ''
                      prime-agent portOverrides pins a server that is enabled
                      but not a local (stdio) bridge: ${
                        builtins.concatStringsSep ", " (
                          lib.filter (n: enabled ? ${n} && !(localServers ? ${n})) (lib.attrNames prime-agent.portOverrides)
                        )
                      }. portOverrides only applies to local MCP servers
                      bridged by mcp-proxy; remote (url) servers have no
                      port.
                    '';
                  }
                  {
                    assertion = duplicatePorts == [ ];
                    message = ''
                      prime-agent MCP bridge port collision: ${
                        builtins.concatStringsSep ", " (map (e: "${e.name} -> ${toString e.p}") duplicatePorts)
                      }. portOverrides pins are honored verbatim, so two
                      servers resolving to one port must be re-pinned.
                    '';
                  }
                  {
                    assertion = missingExtensions == [ ];
                    message = ''
                      icedos.applications.prime-agent.builtinExtensions references upstream
                      prime-agent example extensions that do not exist:
                      ${builtins.concatStringsSep ", " missingExtensions}
                      Each name is a folder/file under
                      <prime-agent>/lib/prime-agent/examples/extensions/.
                    '';
                  }
                  {
                    # Both load a "cost-footer" extension and would double-render.
                    assertion = !prime-agent.costFooter || !(prime-agent.extensions ? "cost-footer");
                    message = ''
                      icedos.applications.prime-agent.extensions already declares
                      "cost-footer"; the built-in cost footer ships the same
                      extension. Remove the inline declaration or set
                      costFooter = false.
                    '';
                  }
                  {
                    assertion = lib.all (n: builtins.match "[A-Za-z0-9._-]+" n != null) (
                      lib.attrNames prime-agent.extensions
                    );
                    message = ''
                      icedos.applications.prime-agent.extensions names must be
                      simple: ${
                        builtins.concatStringsSep ", " (
                          lib.filter (n: builtins.match "[A-Za-z0-9._-]+" n == null) (lib.attrNames prime-agent.extensions)
                        )
                      }
                    '';
                  }
                ];

                # Login shells read home.sessionVariables; the graphical session needs systemd.user.
                home.sessionVariables = primeEnv;
                systemd.user.sessionVariables = primeEnv;

                home.file = mkMerge (
                  (lib.mapAttrsToList skillFiles enabled)
                  ++ extensionHomeFiles
                  ++ extensionLocalHomeFiles
                  ++ [
                    # No shell hooks; extensions auto-load from <agentDir>/extensions/*.ts.
                    (mkIf peonPingEnabled {
                      "${relDataDir}/extensions/peon-ping.ts".source = pkgs.replaceVars ./lib/peon-ping.ts {
                        # Installed by peon-ping's hm module; bin/peon carries its own PATH.
                        peonSh = "${config.home.homeDirectory}/.openpeon/peon.sh";
                      };
                    })
                    # Live session cost (USD) + token totals in the TUI bottom bar.
                    (mkIf prime-agent.costFooter {
                      "${relDataDir}/extensions/cost-footer".source = ./lib/cost-footer;
                    })
                  ]
                );

                systemd.user.services = mkMerge (lib.mapAttrsToList service localServers);

                home.activation.seed-prime-agent = lib.hm.dag.entryAfter [
                  "writeBoundary"
                ] seedScript;

                # Zed has no right-panel reveal target, so spawn into the terminal dock.
                programs.zed-editor.userTasks = lib.mkIf (config.programs.zed-editor.enable or false) [
                  {
                    label = "prime-agent";
                    command = "icedos";
                    args = [
                      "prime-agent"
                    ];
                    use_new_terminal = true;
                    allow_concurrent_runs = true;
                    reveal = "always";
                    reveal_target = "dock";
                    hide = "never";
                  }
                ];

                # Merges with the user's own keymap.json by context.
                programs.zed-editor.userKeymaps = lib.mkIf (config.programs.zed-editor.enable or false) [
                  {
                    context = "Workspace";
                    bindings = {
                      ${prime-agent.keybind} = [
                        "task::Spawn"
                        {
                          task_name = "prime-agent";
                        }
                      ];
                    };
                  }
                  {
                    # Zed's terminal lacks the kitty keyboard protocol; send the
                    # CSI-u shift+enter both prime-agent and Claude Code parse.
                    context = "Terminal";
                    bindings = {
                      shift-enter = [
                        "terminal::SendText"
                        # Nix has no \u escapes; parse the JSON escape to a real ESC.
                        (builtins.fromJSON "\"\\u001b[13;2u\"")
                      ];
                    };
                  }
                ];
              }
            )
          ];
        }
      )
    ];

  meta.name = "prime-agent";
}
