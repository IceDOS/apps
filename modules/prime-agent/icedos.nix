{ icedosLib, lib, ... }:

{
  options.icedos.applications.prime-agent =
    let
      inherit (lib) importTOML;

      inherit (icedosLib)
        mkAttrsOfOption
        mkIntBetweenOption
        mkStrListOption
        mkStrOption
        mkSubmoduleAttrsOption
        ;

      inherit ((importTOML ./config.toml).icedos.applications.prime-agent)
        dataDir
        defaultModel
        defaultProvider
        portBase
        portOverrides
        skillDirs
        ;
    in
    {
      defaultProvider = mkStrOption { default = defaultProvider; };
      defaultModel = mkStrOption { default = defaultModel; };

      # Where prime-agent keeps its data. "" resolves to $XDG_CONFIG_HOME/prime-agent;
      # $XDG_CONFIG_HOME / $XDG_DATA_HOME / $HOME / ~ are expanded per user.
      dataDir = mkStrOption { default = dataDir; };

      skillDirs = mkStrListOption { default = skillDirs; };

      # First bridge port; each local server gets portBase + sha256(name) mod 200.
      # Bound is 65335 so the derived port stays <= 65535.
      portBase = mkIntBetweenOption {
        path = "icedos.applications.prime-agent.portBase";
        source = ./config.toml;
        default = portBase;
      } 0 65335;

      # Pin a server to an exact port. Pins are system-wide, so effectively
      # single-user; derived ports fold the username in and cannot collide.
      portOverrides = mkAttrsOfOption { default = portOverrides; } (lib.types.ints.between 1 65535);

      # One empty entry per normal user (materialized by genDefaults below); the
      # home-manager sharedModule applies to exactly those users.
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
          # peon-ping is a standalone module and may not be loaded at all;
          # guard defensively, the same way opencode's module does.

          peonPingEnabled = (config.icedos.applications.peon-ping.users or { }) != { };
        in
        {
          # Not in nixpkgs yet: package.nix is a copy of nixpkgs PR #550774 at 0.7.3.
          # Drop this overlay, package.nix and the patch once that PR merges.
          nixpkgs.overlays = [
            (final: _prev: {
              prime-agent = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.prime-agent ];

          icedos.applications.prime-agent.users = icedosLib.users.genDefaults {
            inherit (config.icedos) users;
          };
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
                    # Strip trailing slashes so "$HOME/" degenerates into the "$HOME" case
                    # the in-home assertion rejects, not a leading-slash relDataDir.
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
                # home.file keys are $HOME-relative. Only in-home dataDirs are supported
                # (asserted below).
                relDataDir = lib.removePrefix (config.home.homeDirectory + "/") dataDir;
                # ---- shared MCP registry ----
                # Also consumed by opencode; gated on programs.mcp.enable, where hm validates it.
                registry = if config.programs.mcp.enable or false then config.programs.mcp.servers or { } else { };
                # enabled/disabled both turn a server off; home-manager resolves them in a
                # helper it does not export, so mirror it.
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
                # Per-user: folding the username in keeps two users' bridges off each
                # other's ports. portOverrides pins stay system-wide.
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
                    # Pins are reserved up front so a derived port bumps around them;
                    # genuine double pins fail in the assertions below.
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

                # Routed through home-manager's transform so freeform keys (timeout) survive.
                # command/args/env are registry-side; prime-agent only ever speaks HTTP.
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

                # Local bridges accept any token, so a dummy satisfies _resolve_token().
                # Remotes get none: the header reaches their server and can be rejected.
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

                # Remote server with nothing to authenticate with: no bearer env var,
                # no OAuth.
                isNoAuthRemote =
                  s: s.command == null && (s.bearerTokenEnvVar or null) == null && !(s.oauth or false);

                # Seed merge is seed-wins, so empty values would reset TUI-chosen ones.
                # mcpServers always rides along: the registry is declarative.
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
                    # Upstream defaults this to true.
                    telemetry.enabled = false;
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

                # Nix strips a `''` block's common indent, which would leave this method
                # at column 0 -- a module-level function rather than a class member.
                indentPy =
                  block:
                  concatStringsSep "\n" (
                    map (line: if line == "" then "" else "    " + line) (splitString "\n" block)
                  );

                # _open_session always sends `Authorization: Bearer <token>`, which a
                # keyless endpoint that validates the header rejects. Connect without it.
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
                    # _token() checks bearer_token_env before auth.json; these servers are
                    # deliberately excluded from the credential seed.
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
                # systemd does not expand `$` in Environment=; double `%` so a value is
                # not read as a specifier.
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
                # `env` may hold secret file refs ({ file = ...; }); home-manager's helper
                # resolves them into a wrapper and leaves literals for Environment=.
                withEnvFiles = name: s: lib.hm.mcp.wrapEnvFilesCommand { inherit pkgs name; } s;
                # mcp-proxy serves /mcp on the port urlFor expects. --pass-environment is
                # required: unlike supergateway's `sh -c` it hands the child no environment.
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

                # zen 429s unless identified as an opencode client; built-in entry has no headers.
                opencodeVersion = config.programs.opencode.package.version or pkgs.opencode.version;

                modelsJson = builtins.toJSON {
                  providers.opencode = {
                    headers = {
                      "User-Agent" = "opencode/${opencodeVersion}";
                    };
                    apiKey = "!node -p 'JSON.parse(require(\"fs\").readFileSync(process.env.HOME + \"/.local/share/opencode/auth.json\", \"utf8\")).opencode.key'";
                  };
                };

                modelsFile = pkgs.writeText "prime-agent-models.json" modelsJson;
                # ---- first-run seed ----
                # Idempotent: never clobbers state prime-agent writes itself.

                seedSettingsFile = pkgs.writeText "prime-agent-settings.json" (builtins.toJSON seedSettings);
                dummyCredsFile = pkgs.writeText "prime-agent-auth-seed.json" (builtins.toJSON dummyCreds);
                # `install` not `cp` (cp copies the store read-only mode), `+` not `*` for
                # auth.json (`*` recurses into credentials), `--slurpfile` (jq 1.8 dropped --argfile).
                seedScript = ''
                  mkdir -p "${dataDir}"

                  SETTINGS="${dataDir}/settings.json"
                  if [ ! -f "$SETTINGS" ]; then
                    install -m 0644 "${seedSettingsFile}" "$SETTINGS"
                  else
                    ${pkgs.jq}/bin/jq -n --slurpfile a "$SETTINGS" --slurpfile b "${seedSettingsFile}" '$a[0] * $b[0]' > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
                  fi

                  MODELS="${dataDir}/models.json"
                  if [ ! -f "$MODELS" ]; then
                    install -m 0644 "${modelsFile}" "$MODELS"
                  else
                    ${pkgs.jq}/bin/jq -n --slurpfile a "$MODELS" --slurpfile b "${modelsFile}" '$a[0] * $b[0]' > "$MODELS.tmp" && mv "$MODELS.tmp" "$MODELS"
                  fi

                  AUTH="${dataDir}/auth.json"
                  if [ ! -f "$AUTH" ]; then
                    printf '%s\n' '{}' > "$AUTH"
                  fi
                  ${pkgs.jq}/bin/jq -n --slurpfile a "$AUTH" --slurpfile b "${dummyCredsFile}" '$a[0] + $b[0]' > "$AUTH.tmp" && mv "$AUTH.tmp" "$AUTH"
                  # Retract a dummy we seeded, but only if the entry is still exactly ours.
                  ${pkgs.jq}/bin/jq -n --slurpfile a "$AUTH" --slurpfile k "${remoteCredKeysFile}" 'reduce $k[0][] as $key ($a[0]; if .[$key] == {"type":"api_key","key":"dummy"} then del(.[$key]) else . end)' > "$AUTH.tmp" && mv "$AUTH.tmp" "$AUTH"
                '';

                # The env pair that relocates prime-agent (see the dual-write
                # comment in the mkIf block below).
                primeEnv = {
                  PRIME_AGENT_CODING_AGENT_DIR = dataDir;
                  PRIME_AGENT_KERNEL_VENV = "${dataDir}/kernel-venv";
                };
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
                ];
                # Dual-written: home.sessionVariables for login shells, systemd.user for
                # the graphical session (only re-read on re-login).
                home.sessionVariables = primeEnv;
                systemd.user.sessionVariables = primeEnv;

                home.file = mkMerge (
                  (lib.mapAttrsToList skillFiles enabled)
                  ++ [
                    # prime-agent has no shell hooks; extensions are the hook surface,
                    # auto-discovered from <agentDir>/extensions/*.ts.
                    (mkIf peonPingEnabled {
                      "${relDataDir}/extensions/peon-ping.ts".source = pkgs.replaceVars ./lib/peon-ping.ts {
                        # Installed unconditionally by peon-ping's hm module; the bin/peon
                        # wrapper carries its own runtime PATH.
                        peonSh = "${config.home.homeDirectory}/.openpeon/peon.sh";
                      };
                    })
                  ]
                );

                systemd.user.services = mkMerge (lib.mapAttrsToList service localServers);

                home.activation.seed-prime-agent = lib.hm.dag.entryAfter [
                  "writeBoundary"
                ] seedScript;
                # Copies the selection's location only, with no trailing newline, so a paste
                # never submits. Wrapper is hermetic: the task terminal's PATH is untrusted.
                home.packages = [
                  (pkgs.writeShellScriptBin "prime-add" ''
                    # wl-copy execs `cat` to feed itself stdin, so coreutils
                    # must be on PATH too for the hermetic guarantee.
                    export PATH=${
                      lib.makeBinPath [
                        pkgs.wl-clipboard
                        pkgs.xclip
                        pkgs.libnotify
                        pkgs.coreutils
                      ]
                    }"''${PATH:+:$PATH}"
                    exec ${pkgs.python3Minimal}/bin/python3 ${./lib/prime-add.py} "$@"
                  '')
                ];
                # Zed has no right-panel reveal target, so spawn into the terminal dock
                # and drag it right. Concurrent runs allowed.
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
                  {
                    # Selection travels via env, not the command line (build_no_quote would
                    # dump raw code into zsh -c). Empty selection leaves the task unresolved.
                    label = "prime-add: copy selection";
                    command = "prime-add";
                    args = [ ];
                    env = {
                      PRIME_ADD_SELECTED_TEXT = "$ZED_SELECTED_TEXT";
                    };
                    use_new_terminal = false;
                    allow_concurrent_runs = true;
                    reveal = "never";
                    hide = "on_success";
                  }
                ];
                # ctrl-alt-p spawns the task above. Workspace context; merges with the
                # user's own keymap.json by context.
                programs.zed-editor.userKeymaps = lib.mkIf (config.programs.zed-editor.enable or false) [
                  {
                    context = "Workspace";
                    bindings = {
                      "ctrl-alt-p" = [
                        "task::Spawn"
                        {
                          task_name = "prime-agent";
                        }
                      ];
                    };
                  }
                  {
                    # ctrl-alt-c copies selection + location. Free in Zed's Linux default
                    # editor keymap (it only collides in panel contexts).
                    context = "Editor";
                    bindings = {
                      "ctrl-alt-c" = [
                        "task::Spawn"
                        {
                          task_name = "prime-add: copy selection";
                        }
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
