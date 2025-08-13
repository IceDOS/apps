{ icedosLib, ... }:

{
  options.icedos.applications.steam =
    let
      inherit (icedosLib) mkBoolOption;
    in
    {
      beta = mkBoolOption { default = false; };
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
            hasAttr
            mapAttrs
            mkIf
            ;

          cfg = config.icedos;
          applications = cfg.applications;
          steamdeck = hasAttr "steamdeck" cfg.hardware.devices;
        in
        {
          home-manager.users = mapAttrs (user: _: {
            home = {
              file = {
                # Enable steam beta
                ".local/share/Steam/package/beta" = mkIf (applications.steam.beta) {
                  text = if (hasAttr "steamdeck" cfg.hardware.devices) then "steamdeck_publicbeta" else "publicbeta";
                };

                # Enable slow steam downloads workaround
                ".local/share/Steam/steam_dev.cfg" = mkIf (applications.steam.downloadsWorkaround) {
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
        }
      )
    ];

  meta.name = "steam";
}
