{ icedosLib, lib, ... }:

{
  options.icedos.applications.steam =
    let
      inherit (icedosLib) mkBoolOption mkStrListOption;

      inherit
        (
          let
            inherit (lib) importTOML;
          in
          (importTOML ./config.toml).icedos.applications.steam
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
    { repoUrl, ... }:
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
          hasGamescope = config.programs.gamescope.enable;

          hasProtonLaunch = icedosLib.hasModule {
            inherit config repoUrl;
            name = "proton-launch";
          };

          hasMe3 = icedosLib.hasModule {
            inherit config repoUrl;
            name = "me3";
          };

          hasReigntweak = icedosLib.hasModule {
            inherit config repoUrl;
            name = "reigntweak";
          };

          optionalGamescope = optional hasGamescope pkgs.gamescope;
          optionalProtonLaunch = optional hasProtonLaunch pkgs.proton-launch;
          optionalMe3 = optional hasMe3 pkgs.me3;
          optionalReigntweak = optional hasReigntweak pkgs.reigntweak;
          steamExtras =
            extraPackages ++ optionalGamescope ++ optionalProtonLaunch ++ optionalMe3 ++ optionalReigntweak;
          optionalSunshineHeadlessSteamOS = applications.steam.headless-session.steamOS or false;
          session = hasAttr "session" applications.steam;

          steamdeck = icedosLib.hasModule {
            inherit config;
            url = "github:icedos/hardware";
            name = "steamdeck";
          };

          # raw = definer; resolved = consumer (reads programs.steam.package).
          steamPkg = (import ./lib/resolved-steam.nix) { inherit config pkgs; };

          # When steamOS + beta are both on, wrap desktop Steam with -steamos3
          # so the beta channel stays as steamdeck_publicbeta (no desktop/headless de-sync).
          wrapSteamos3 =
            pkg:
            pkgs.symlinkJoin {
              name = "steam-steamos3";
              paths = [ pkg ];
              nativeBuildInputs = [ pkgs.makeWrapper ];
              postBuild = ''
                mv $out/bin/steam $out/bin/steam.real
                makeWrapper $out/bin/steam.real $out/bin/steam --add-flags "-steamos3"
              '';
            };

          steamFinal =
            let
              # Any extras at all require the override; extras-only hosts must
              # not fall through to null or their packages get dropped.
              steamBase =
                if steamExtras == [ ] then
                  steamPkg.raw
                else
                  steamPkg.raw.override {
                    extraPkgs = _: steamExtras;
                  };
            in
            if optionalSunshineHeadlessSteamOS && beta then
              wrapSteamos3 steamBase
            else
              steamBase;
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

              home.packages = if !session then [ steamFinal ] else [ ];
            }
          ];

          # DEFINED here → must use `raw` (not `resolved`, which reads this option).
          programs.steam = {
            enable = steamdeck || session;
            extraPackages = steamExtras;
            package = steamPkg.raw;
          };

          # Explicit `d` rules before `L+` so tmpfiles doesn't create dirs as root.
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
