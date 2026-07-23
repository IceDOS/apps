{ icedosLib, lib, ... }:

{
  options.icedos.applications.steam =
    let
      inherit (icedosLib) mkBoolOption mkStrListOption;

      inherit
        (
          let
            inherit (lib) readFile;
          in
          (fromTOML (readFile ./config.toml)).icedos.applications.steam
        )
        beta
        cpuUsageWorkaround
        downloadsWorkaround
        extraPackages
        ;
    in
    {
      beta = mkBoolOption { default = beta; };
      cpuUsageWorkaround = mkBoolOption { default = cpuUsageWorkaround; };
      downloadsWorkaround = mkBoolOption { default = downloadsWorkaround; };
      extraPackages = mkStrListOption { default = extraPackages; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          icedosLib,
          lib,
          pkgs,
          ...
        }:

        let
          inherit (config) icedos;
          inherit (icedos) applications users;
          inherit (icedosLib.pkgs) mapper;

          inherit (lib)
            attrNames
            concatMap
            hasAttr
            length
            mkIf
            optional
            optionals
            ;

          inherit (applications.steam) beta cpuUsageWorkaround downloadsWorkaround;

          extraPackages = mapper pkgs applications.steam.extraPackages;
          hasExtraPackages = length extraPackages != 0;
          hasGamescope = hasAttr "gamescope" applications;
          hasProtonLaunch = hasAttr "proton-launch" applications;
          optionalGamescope = optional hasGamescope pkgs.gamescope;
          optionalProtonLaunch = optional hasProtonLaunch pkgs.proton-launch;
          optionalSunshineHeadlessSteamOS = applications.steam.headless-session.steamOS or false;
          session = hasAttr "session" applications.steam;
          steamdeck = hasAttr "steamdeck" (icedos.hardware.devices or { });
          steamPkg = pkgs.steam;
        in
        {
          home-manager.sharedModules = [
            {
              xdg.dataFile = {
                "Steam/package/beta" = mkIf beta {
                  text =
                    if (steamdeck || optionalSunshineHeadlessSteamOS) then "steamdeck_publicbeta" else "publicbeta";
                };

                "Steam/steam_dev.cfg" = mkIf downloadsWorkaround {
                  text = ''
                    @nClientDownloadEnableHTTP2PlatformLinux 0
                  '';
                };
              };

              home.packages =
                if (!hasGamescope && !hasProtonLaunch && !hasExtraPackages && !session) then
                  [ steamPkg ]
                else if ((hasGamescope || hasProtonLaunch) && !session) then
                  [
                    (steamPkg.override {
                      extraPkgs = pkgs: extraPackages ++ optionalGamescope ++ optionalProtonLaunch;
                    })
                  ]
                else
                  [ ];
            }
          ];

          programs.steam = {
            enable = steamdeck || session;
            extraPackages = extraPackages ++ optionalGamescope ++ optionalProtonLaunch;
            package = steamPkg;
          };

          # The `L+` symlink rule does not auto-create intermediate parent
          # directories with user ownership; without explicit `d` rules first,
          # systemd-tmpfiles may create them as root and break later HM
          # activation steps that try to write inside Steam/.
          systemd.tmpfiles.rules = concatMap (
            user:
            let
              home = config.users.users.${user}.home;
            in
            optional (
              beta || cpuUsageWorkaround || downloadsWorkaround
            ) "d ${home}/.local/share/Steam 0755 ${user} users -"
            ++ optional beta "d ${home}/.local/share/Steam/package 0755 ${user} users -"
            ++ optionals cpuUsageWorkaround [
              "d ${home}/.local/share/Steam/steamapps 0755 ${user} users -"
              "d ${home}/.local/share/Steam/steamapps/compatdata 0755 ${user} users -"
              "L+ ${home}/.local/share/Steam/steamapps/compatdata/0 - - - - /dev/null"
            ]
          ) (attrNames users);
        }
      )
    ];

  meta.name = "steam";
}
