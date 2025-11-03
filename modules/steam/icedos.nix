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
          lib,
          pkgs,
          ...
        }:

        let
          inherit (config.icedos) applications hardware users;
          inherit (hardware) devices;

          inherit (lib)
            attrNames
            hasAttr
            length
            mapAttrs
            mkIf
            optional
            ;

          inherit (pkgs) steam;

          inherit (applications.steam)
            beta
            cpuUsageWorkaround
            downloadsWorkaround
            extraPackages
            ;

          hasExtraPackages = length extraPackages != 0;
          hasGamescope = hasAttr "gamescope" applications;
          hasProtonLaunch = hasAttr "proton-launch" applications;
          optionalGamescope = optional hasGamescope pkgs.gamescope;
          optionalProtonLaunch = optional hasProtonLaunch pkgs.proton-launch;
          session = hasAttr "session" applications.steam;
          steamdeck = hasAttr "steamdeck" devices;
        in
        {
          home-manager.users = mapAttrs (user: _: {
            home = {
              file = {
                ".local/share/Steam/package/beta" = mkIf beta {
                  force = true;
                  text = if steamdeck then "steamdeck_publicbeta" else "publicbeta";
                };

                ".local/share/Steam/steam_dev.cfg" = mkIf downloadsWorkaround {
                  force = true;

                  text = ''
                    @nClientDownloadEnableHTTP2PlatformLinux 0
                  '';
                };
              };

              packages =
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
            };
          }) users;

          programs.steam = {
            enable = steamdeck || session;
            extest.enable = steamdeck;
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
