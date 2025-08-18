{ icedosLib, ... }:

{
  options.icedos.applications.steam =
    let
      inherit (icedosLib) mkBoolOption;
    in
    {
      beta = mkBoolOption { default = false; };
      cpuUsageWorkaround = mkBoolOption { default = false; };
      downloadsWorkaround = mkBoolOption { default = false; };
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
                  text = if (hasAttr "steamdeck" cfg.hardware.devices) then "steamdeck_publicbeta" else "publicbeta";
                };

                # Enable slow steam downloads workaround
                ".local/share/Steam/steam_dev.cfg" = mkIf (steam.downloadsWorkaround) {
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
