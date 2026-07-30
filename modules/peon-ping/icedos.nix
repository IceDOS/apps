{ icedosLib, lib, ... }:

{
  inputs.peon-ping = {
    url = "github:PeonPing/peon-ping";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # Standalone module: peon-ping owns its own per-user option
  # `icedos.applications.peon-ping.users.<name>`. It is NOT part of claude-code —
  # claude-code and opencode merely *consume* it (they read this option to detect
  # the module and wire their hooks/plugins).
  options.icedos.applications.peon-ping.users =
    let
      inherit (lib) head importTOML;

      inherit (icedosLib)
        mkAttrsOption
        mkBoolOption
        mkFloatBetweenOption
        mkIntBetweenOption
        mkStrListOption
        mkStrOption
        mkSubmoduleAttrsOption
        mkSubmoduleListOption
        ;

      inherit ((importTOML ./config.toml).icedos.applications.peon-ping.users.username)
        categories
        defaultPack
        desktopNotifications
        packs
        silentWindowSeconds
        suppressSubagentComplete
        volume
        ;

      customPackTemplate = head (importTOML ./custom-packs.toml)
        .icedos.applications.peon-ping.users.username.customPacks;
    in
    mkSubmoduleAttrsOption { default = { }; } {
      defaultPack = mkStrOption { default = defaultPack; };

      volume = mkFloatBetweenOption {
        path = "icedos.applications.peon-ping.users.<u>.volume";
        source = ./config.toml;
        default = volume;
      } 0.0 1.0;

      desktopNotifications = mkBoolOption { default = desktopNotifications; };
      suppressSubagentComplete = mkBoolOption { default = suppressSubagentComplete; };

      # `Stop` fires at the end of *every* assistant turn, not once per task, so
      # `task.complete` alone is noisy. Non-zero suppresses it when the turn took
      # less than N seconds; the idle/stuck ping bypasses this window entirely.
      silentWindowSeconds = mkIntBetweenOption {
        path = "icedos.applications.peon-ping.users.<u>.silentWindowSeconds";
        source = ./config.toml;
        default = silentWindowSeconds;
      } 0 3600;

      # Per-category sound switches. Keys (all default on except task.acknowledge):
      #   session.start  task.acknowledge  task.complete  task.error
      #   input.required  resource.limit  user.spam
      # task.complete covers both turn-end and idle/stuck; input.required covers
      # permission prompts and elicitation questions.
      categories = mkAttrsOption { default = categories; };

      packs = mkStrListOption { default = packs; };

      customPacks = mkSubmoduleListOption { default = [ ]; } {
        name = mkStrOption { default = customPackTemplate.name; };
        owner = mkStrOption { default = customPackTemplate.owner; };
        repo = mkStrOption { default = customPackTemplate.repo; };
        rev = mkStrOption { default = customPackTemplate.rev; };
        hash = mkStrOption { default = customPackTemplate.hash; };
      };
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
          inherit (lib) filter optionalAttrs;
          peonUsers = config.icedos.applications.peon-ping.users;
          peonPkg = inputs.peon-ping.packages.${pkgs.system}.default;

          renderCustomPack = cp: {
            inherit (cp) name;
            src = pkgs.fetchFromGitHub {
              inherit (cp)
                owner
                repo
                rev
                hash
                ;
            };
          };

          renderInstallPacks =
            u: u.packs ++ (map renderCustomPack (filter (cp: cp.name != "") u.customPacks));

          renderPeonSettings =
            u:
            {
              default_pack = u.defaultPack;
              volume = u.volume;
              desktop_notifications = u.desktopNotifications;
              suppress_subagent_complete = u.suppressSubagentComplete;
              silent_window_seconds = u.silentWindowSeconds;
            }
            // optionalAttrs (u.categories != { }) { categories = u.categories; };
        in
        {
          icedos.applications.peon-ping.users = icedosLib.users.genDefaults {
            inherit (config.icedos) users;
          };

          home-manager.sharedModules = [
            inputs.peon-ping.homeManagerModules.default
            (
              { config, lib, ... }:

              let
                peonUserCfg = peonUsers.${config.home.username} or null;
              in
              lib.mkIf (peonUserCfg != null) {
                programs.peon-ping = {
                  enable = true;
                  package = peonPkg;
                  claudeCodeIntegration = false;
                  settings = renderPeonSettings peonUserCfg;
                  installPacks = renderInstallPacks peonUserCfg;
                };

                home.file.".claude/hooks/peon-ping/peon.sh".source = "${peonPkg}/bin/peon";
              }
            )
          ];
        }
      )
    ];

  meta.name = "peon-ping";
}
