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
          inherit (config.icedos) applications hardware users;
          inherit (hardware) devices;
          inherit (icedosLib.pkgs) mapper;

          inherit (lib)
            attrNames
            concatMap
            hasAttr
            length
            mkIf
            optional
            ;

          inherit (applications.steam) beta cpuUsageWorkaround downloadsWorkaround;

          extraPackages = mapper pkgs applications.steam.extraPackages;
          hasExtraPackages = length extraPackages != 0;
          hasGamescope = hasAttr "gamescope" applications;
          hasMillennium = hasAttr "millennium" applications.steam;
          hasProtonLaunch = hasAttr "proton-launch" applications;
          optionalGamescope = optional hasGamescope pkgs.gamescope;
          optionalProtonLaunch = optional hasProtonLaunch pkgs.proton-launch;
          session = hasAttr "session" applications.steam;
          steamdeck = hasAttr "steamdeck" devices;
          steamPkg = if hasMillennium then pkgs.millennium-steam else pkgs.steam;
        in
        {
          home-manager.sharedModules = [
            {
              xdg.dataFile = {
                "Steam/package/beta" = mkIf beta {
                  force = true;
                  text = if steamdeck then "steamdeck_publicbeta" else "publicbeta";
                };

                "Steam/steam_dev.cfg" = mkIf downloadsWorkaround {
                  force = true;

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
            package = mkIf hasMillennium steamPkg;
          };

          # The `L+` symlink rule does not auto-create intermediate parent
          # directories with user ownership; without explicit `d` rules first,
          # systemd-tmpfiles may create them as root and break later HM
          # activation steps that try to write inside Steam/.
          systemd.tmpfiles.rules = mkIf cpuUsageWorkaround (
            concatMap (user: [
              "d /home/${user}/.local/share/Steam 0755 ${user} users -"
              "d /home/${user}/.local/share/Steam/steamapps 0755 ${user} users -"
              "d /home/${user}/.local/share/Steam/steamapps/compatdata 0755 ${user} users -"
              "L+ /home/${user}/.local/share/Steam/steamapps/compatdata/0 - - - - /dev/null"
            ]) (attrNames users)
          );
        }
      )
    ];

  meta.name = "steam";
}
