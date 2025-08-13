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
            hasAttr
            mapAttrs
            mkIf
            ;

          cfg = config.icedos;
          package = [ pkgs.gamescope ];
          ifSteam = deck: hasAttr "steam" cfg.applications && deck;
          steamdeck = hasAttr "steamdeck" cfg.hardware.devices;
        in
        {
          environment.systemPackages = package;
          programs.steam.extraPackages = mkIf (ifSteam steamdeck) package;

          home-manager.users = mapAttrs (user: _: {
            home.packages = mkIf (ifSteam (!steamdeck) && !cfg.applications.proton-launch) [
              (pkgs.steam.override { extraPkgs = pkgs: package; })
            ];
          }) cfg.users;
        }
      )
    ];

  meta.name = "gamescope";
}
