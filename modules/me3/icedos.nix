{ icedosLib, ... }:

{
  options.icedos.applications.me3.profiles =
    let
      inherit (icedosLib) mkSubmoduleListOption mkStrOption mkStrListOption;
    in
    mkSubmoduleListOption { default = [ ]; } {
      config = mkStrOption { default = ""; };
      dependencies = mkStrListOption { default = [ ]; };
      name = mkStrOption { default = ""; };
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
        {
          nixpkgs.overlays = [
            (final: super: {
              me3 = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages =
            let
              inherit (pkgs) me3;
            in
            [
              me3
            ];

          home-manager.users =
            let
              inherit (lib) listToAttrs mapAttrs;
              cfg = config.icedos;
            in
            mapAttrs (user: _: {
              home.file =
                let
                  inherit (icedosLib) abortIf;

                  inherit (lib)
                    concatMapStringsSep
                    filter
                    foldl'
                    head
                    length
                    ;

                  inherit (config.icedos.applications.me3) profiles;
                  inherit (pkgs) me3;
                  homeWindowsBinPath = ".local/share/me3/windows-bin";
                  windowsBinPath = "${me3}/share/me3/windows-bin";
                in
                {
                  "${homeWindowsBinPath}/me3-launcher.exe".source = "${windowsBinPath}/me3-launcher.exe";
                  "${homeWindowsBinPath}/me3_mod_host.dll".source = "${windowsBinPath}/me3_mod_host.dll";
                }
                // foldl' (acc: atrrset: acc // atrrset) { } (
                  map (
                    profile:
                    let
                      filterProfiles = name: profiles: (filter (profile: profile.name == name) profiles);
                      duplicateProfiles = length (filterProfiles profile.name cfg.applications.me3.profiles);
                      getProfileByName = name: head (filter (p: p.name == name) profiles);

                      dependencies = concatMapStringsSep "\n" (
                        depName: (getProfileByName depName).config
                      ) profile.dependencies;

                      config =
                        if
                          (abortIf (duplicateProfiles > 1)
                            ''${toString duplicateProfiles} me3 profiles named "${profile.name}" detected - profile names have to be unique!''
                          )
                        then
                          profile.config
                        else
                          "";
                    in
                    {
                      ".config/me3/profiles/${profile.name}.me3".text = ''
                        ${dependencies}
                        ${config}
                      '';
                    }
                  ) profiles
                );
            }) (listToAttrs (icedosLib.getNormalUsers { inherit (config.users) users; }));
        }
      )
    ];

  meta.name = "me3";
}
