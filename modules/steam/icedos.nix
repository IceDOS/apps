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
        hardwareSupport
        ;
    in
    {
      beta = mkBoolOption { default = beta; };
      cpuUsageWorkaround = mkBoolOption { default = cpuUsageWorkaround; };
      downloadsWorkaround = mkBoolOption { default = downloadsWorkaround; };
      extraPackages = mkStrListOption { default = extraPackages; };
      hardwareSupport = mkBoolOption { default = hardwareSupport; };
    };

  outputs.nixosModules =
    { repoUrl, inputs, ... }:
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
            mkForce
            mkIf
            optional
            optionals
            ;

          inherit (applications.steam)
            beta
            cpuUsageWorkaround
            downloadsWorkaround
            hardwareSupport
            ;

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

          hasShadps4 = icedosLib.hasModule {
            inherit config repoUrl;
            name = "shadps4";
          };

          optionalGamescope = optional hasGamescope pkgs.gamescope;
          optionalProtonLaunch = optional hasProtonLaunch pkgs.proton-launch;
          optionalMe3 = optional hasMe3 pkgs.me3;
          optionalReigntweak = optional hasReigntweak pkgs.reigntweak;

          optionalShadps4 = optionals hasShadps4 (
            with pkgs;
            [
              shadps4
              shadps4-qtlauncher
            ]
          );

          # -steamos3 spawns SteamOS-only helpers; stand-ins from jovian-stubs keep
          # the runtime log clean of missing steamos-select-branch/polkit errors.
          steamosShims =
            let
              stubs = (pkgs.extend inputs.jovian.overlays.default).jovian-stubs;
            in
            # Only the binaries Steam calls; excludes jovian's pkexec/sudo/holo-* stand-ins.
            optional optionalSunshineHeadlessSteamOS (
              pkgs.runCommandLocal "steamos-shims" { } ''
                mkdir -p $out/bin/steamos-polkit-helpers
                ln -s ${stubs}/bin/steamos-select-branch $out/bin/steamos-select-branch
                ln -s ${stubs}/bin/steamos-polkit-helpers/steamos-update $out/bin/steamos-polkit-helpers/steamos-update
                ln -s ${stubs}/bin/steamos-polkit-helpers/jupiter-biosupdate $out/bin/steamos-polkit-helpers/jupiter-biosupdate
                ln -s ${stubs}/bin/steamos-polkit-helpers/jupiter-dock-updater $out/bin/steamos-polkit-helpers/jupiter-dock-updater
              ''
            );

          steamExtras =
            extraPackages
            ++ steamosShims
            ++ optionalGamescope
            ++ optionalProtonLaunch
            ++ optionalMe3
            ++ optionalReigntweak
            ++ optionalShadps4;

          optionalSunshineHeadlessSteamOS = applications.steam.headless-session.steamOS or false;
          session = hasAttr "session" applications.steam;

          steamdeck = icedosLib.hasModule {
            inherit config;
            url = "github:icedos/hardware";
            name = "steamdeck";
          };

          # Modules that define programs.steam use `raw`; consumers use `resolved`.
          steamPkg = (import ./lib/resolved-steam.nix) { inherit config pkgs; };

          # -steamos3 Steam is a separate client with its own stable/beta channels, and it
          # shares this HOME with the headless session, so desktop Steam must run it too.
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
            if optionalSunshineHeadlessSteamOS then wrapSteamos3 steamBase else steamBase;
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

          # Nothing pulls steam-devices-udev-rules in on the home.packages path, and without
          # them pads get no uaccess. programs.steam pulls them in itself, so opting out forces.
          hardware.steam-hardware.enable = if hardwareSupport then true else mkForce false;

          # Defined here, so use `raw`; `resolved` reads this option and would recurse.
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

          icedos.system.tips.list = [
            "Add libraries a game, launcher or app needs with extraPackages under [icedos.applications.steam]."
          ]
          ++ lib.optionals downloadsWorkaround [
            "The Steam download fix is on, so downloads should utilize your full bandwidth."
          ]
          ++ lib.optionals cpuUsageWorkaround [
            "The Steam processor fix is on, so the client stops hogging your CPU."
          ]
          ++ lib.optionals beta [
            "Steam runs on the beta channel; turn beta off in config.toml if something breaks."
          ]
          ++ lib.optionals (!hardwareSupport) [
            "Steam controller udev rules are off, so pads needing uaccess or uinput may not work."
          ];
        }
      )
    ];

  meta.name = "steam";
}
