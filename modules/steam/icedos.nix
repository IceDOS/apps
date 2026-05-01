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
            hasAttr
            length
            mkIf
            optional
            ;

          inherit (pkgs) steam;
          inherit (applications.steam) beta cpuUsageWorkaround downloadsWorkaround;

          extraPackages = mapper pkgs applications.steam.extraPackages;
          hasExtraPackages = length extraPackages != 0;
          hasGamescope = hasAttr "gamescope" applications;
          hasProtonLaunch = hasAttr "proton-launch" applications;
          optionalGamescope = optional hasGamescope pkgs.gamescope;
          optionalProtonLaunch = optional hasProtonLaunch pkgs.proton-launch;
          session = hasAttr "session" applications.steam;
          steamdeck = hasAttr "steamdeck" devices;
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
                  [ steam ]
                else if ((hasGamescope || hasProtonLaunch) && !session) then
                  [
                    (steam.override {
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
          };

          systemd.tmpfiles.rules = mkIf cpuUsageWorkaround (
            map (user: "L+ /home/${user}/.local/share/Steam/steamapps/compatdata/0 - - - - /dev/null") (
              attrNames users
            )
          );
        }
      )
    ];

  meta.name = "steam";
}
