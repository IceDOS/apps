{ icedosLib, ... }:

{
  options.icedos.applications.gamescope = icedosLib.mkBoolOption { default = true; };

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
            mapAttrs
            mkIf
            ;

          cfg = config.icedos;
          package = [ pkgs.gamescope ];
          ifSteam = deck: lib.hasAttr "steam" cfg.applications && deck;
        in
        {
          environment.systemPackages = package;
          programs.steam.extraPackages = mkIf (ifSteam (cfg.hardware.devices.steamdeck)) package;

          home-manager.users = mapAttrs (user: _: {
            home.packages =
              mkIf (ifSteam (!cfg.hardware.devices.steamdeck) && !cfg.applications.proton-launch)
                [
                  (pkgs.steam.override { extraPkgs = pkgs: package; })
                ];
          }) cfg.system.users;
        }
      )
    ];

  meta.name = "gamescope";
}
