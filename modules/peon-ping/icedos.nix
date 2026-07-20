{ icedosLib, lib, ... }:

{
  inputs.peon-ping = {
    url = "github:PeonPing/peon-ping";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  options.icedos.applications.peon-ping.users =
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

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.peon-ping.users.username)
        categories
        defaultPack
        desktopNotifications
        packs
        suppressSubagentComplete
        volume
        ;

      customPackTemplate = head (fromTOML (readFile ./custom-packs.toml))
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
            }
            // optionalAttrs (u.categories != { }) { categories = u.categories; };
        in
        {
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
