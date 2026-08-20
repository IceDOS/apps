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
          hasExtraPackages = length extraPackages != 0;
          hasGamescope = config.programs.gamescope.enable;
          hasProtonLaunch = icedosLib.hasModule {
            inherit config repoUrl;
            name = "proton-launch";
          };
          optionalGamescope = optional hasGamescope pkgs.gamescope;
          optionalProtonLaunch = optional hasProtonLaunch pkgs.proton-launch;
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
              postBuild = ''
                mv $out/bin/steam $out/bin/steam.real
                cat > $out/bin/steam <<'WRAPPER'
                  #!${pkgs.bash}/bin/bash
                  exec "$(dirname "$0")/steam.real" -steamos3 "$@"
                WRAPPER
                chmod +x $out/bin/steam
              '';
            };

          steamFinal =
            let
              steamBase =
                if (!hasGamescope && !hasProtonLaunch && !hasExtraPackages) then
                  steamPkg.raw
                else if (hasGamescope || hasProtonLaunch) then
                  steamPkg.raw.override {
                    extraPkgs = pkgs: extraPackages ++ optionalGamescope ++ optionalProtonLaunch;
                  }
                else
                  null;
            in
            if steamBase == null then
              null
            else if optionalSunshineHeadlessSteamOS && beta then
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

              home.packages = if !session && steamFinal != null then [ steamFinal ] else [ ];
            }
          ];

          # DEFINED here → must use `raw` (not `resolved`, which reads this option).
          programs.steam = {
            enable = steamdeck || session;
            extraPackages = extraPackages ++ optionalGamescope ++ optionalProtonLaunch;
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
