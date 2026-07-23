{ icedosLib, lib, ... }:

{
  inputs.peon-ping = {
    url = "github:PeonPing/peon-ping";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # Contributes a nested `peonPing` submodule to the claude-code per-user option
  # (declared in claude-icedos/…/default). peon-ping is wired as a Claude Code
  # notifier here (installs into ~/.claude/hooks), so its per-user config lives at
  # icedos.applications.claude-code.users.<name>.peonPing and materialises via that
  # module's genDefaults.
  options.icedos.applications.claude-code.users =
    let
      inherit (lib) head readFile;

      inherit (icedosLib)
        mkAttrsOption
        mkBoolOption
        mkFloatBetweenOption
        mkStrListOption
        mkStrOption
        mkSubmoduleAttrsOption
        mkSubmoduleListOption
        ;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.claude-code.users.username.peonPing)
        categories
        defaultPack
        desktopNotifications
        packs
        suppressSubagentComplete
        volume
        ;

      customPackTemplate = head (fromTOML (readFile ./custom-packs.toml))
        .icedos.applications.claude-code.users.username.peonPing.customPacks;
    in
    mkSubmoduleAttrsOption { default = { }; } {
      peonPing = {
        defaultPack = mkStrOption { default = defaultPack; };

        volume = mkFloatBetweenOption {
          path = "icedos.applications.claude-code.users.<u>.peonPing.volume";
          source = ./config.toml;
          default = volume;
        } 0.0 1.0;

        desktopNotifications = mkBoolOption { default = desktopNotifications; };
        suppressSubagentComplete = mkBoolOption { default = suppressSubagentComplete; };
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
          claudeUsers = config.icedos.applications.claude-code.users;
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
            }
            // optionalAttrs (u.categories != { }) { categories = u.categories; };
        in
        {
          # Self-sufficient materialisation: fills claude-code.users for every
          # normal user so peonPing defaults exist even if this module loads
          # without the claude-code default module. Merges idempotently with that
          # module's own genDefaults when both are present.
          icedos.applications.claude-code.users = icedosLib.users.genDefaults {
            inherit (config.icedos) users;
          };

          home-manager.sharedModules = [
            inputs.peon-ping.homeManagerModules.default
            (
              { config, lib, ... }:

              let
                peonUserCfg = claudeUsers.${config.home.username}.peonPing or null;
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
