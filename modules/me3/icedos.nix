{ icedosLib, lib, ... }:

{
  inputs.me3 = {
    url = "github:fn3x/me3";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  options.icedos.applications.me3.profiles =
    let
      inherit (icedosLib) mkSubmoduleListOption mkStrOption mkStrListOption;
      inherit (lib) elemAt readFile;
      profileDefaults = elemAt 0 (fromTOML (readFile ./profiles.toml));
    in
    mkSubmoduleListOption { default = [ ]; } {
      config = mkStrOption { default = profileDefaults.config; };
      dependencies = mkStrListOption { default = profileDefaults.dependencies; };
      name = mkStrOption { default = profileDefaults.name; };
    };

  outputs.nixosModules =
    { inputs, ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          environment.systemPackages = [
            inputs.me3.packages.${pkgs.stdenv.hostPlatform.system}.default
          ];

          home-manager.users =
            let
              inherit (icedosLib) abortIf;

              inherit (lib)
                mapAttrs
                concatMapStringsSep
                filter
                foldl'
                head
                length
                ;

              inherit (config.icedos) applications users;
              inherit (applications.me3) profiles;
            in
            mapAttrs (user: _: {
              home.file = foldl' (acc: attrset: acc // attrset) { } (
                map (
                  profile:
                  let
                    filterProfiles = name: profiles: (filter (profile: profile.name == name) profiles);
                    duplicateProfiles = length (filterProfiles profile.name profiles);
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
            }) users;
        }
      )
    ];

  meta.name = "me3";
}
