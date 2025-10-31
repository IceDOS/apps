{ icedosLib, lib, ... }:

{
  options.icedos.applications.steam =
    let
      inherit (icedosLib) mkBoolOption;
      inherit (defaultConfig) beta cpuUsageWorkaround downloadsWorkaround;

      defaultConfig =
        let
          inherit (lib) readFile;
        in
        (fromTOML (readFile ./config.toml)).icedos.applications.steam;
    in
    {
      beta = mkBoolOption { default = beta; };
      cpuUsageWorkaround = mkBoolOption { default = cpuUsageWorkaround; };
      downloadsWorkaround = mkBoolOption { default = downloadsWorkaround; };
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
            attrNames
            hasAttr
            mapAttrs
            mkIf
            ;

          cfg = config.icedos;
          applications = cfg.applications;
          steam = applications.steam;
          steamdeck = hasAttr "steamdeck" cfg.hardware.devices;
        in
        {
          home-manager.users = mapAttrs (user: _: {
            home = {
              file = {
                # Enable steam beta
                ".local/share/Steam/package/beta" = mkIf (steam.beta) {
                  force = true;
                  text = if (hasAttr "steamdeck" cfg.hardware.devices) then "steamdeck_publicbeta" else "publicbeta";
                };

                # Enable slow steam downloads workaround
                ".local/share/Steam/steam_dev.cfg" = mkIf (steam.downloadsWorkaround) {
                  force = true;

                  text = ''
                    @nClientDownloadEnableHTTP2PlatformLinux 0
                  '';
                };
              };

              packages =
                mkIf (!steamdeck && !(hasAttr "gamescope" applications) && !(hasAttr "proton-launch" applications))
                  [
                    pkgs.steam
                  ];
            };
          }) cfg.users;

          programs.steam = mkIf steamdeck {
            enable = true;
            extest.enable = true;
          };

          systemd.tmpfiles.rules = mkIf steam.cpuUsageWorkaround (
            map (user: "L+ /home/${user}/.local/share/Steam/steamapps/compatdata/0 - - - - /dev/null") (
              attrNames cfg.users
            )
          );
        }
      )
    ];

  meta.name = "steam";
}
