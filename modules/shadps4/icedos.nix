{ icedosLib, lib, ... }:

{

  options.icedos.applications.shadps4.customBuild =
    let
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.shadps4.customBuild)
        enable
        hash
        owner
        repo
        tag
        ;

      inherit (icedosLib) mkBoolOption mkStrOption;
    in
    {
      enable = mkBoolOption { default = enable; };
      hash = mkStrOption { default = hash; };
      owner = mkStrOption { default = owner; };
      repo = mkStrOption { default = repo; };
      tag = mkStrOption { default = tag; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          pkgs,
          ...
        }:

        let
          inherit (pkgs) fetchFromGitHub shadps4;
          customBuild = config.icedos.applications.shadps4.customBuild;
        in
        {
          environment.systemPackages =
            if (customBuild.enable) then
              [
                (shadps4.overrideAttrs (
                  super:
                  let
                    inherit (customBuild)
                      hash
                      owner
                      repo
                      tag
                      ;
                  in
                  {
                    src = fetchFromGitHub {
                      inherit (super.src) fetchSubmodules;

                      inherit
                        hash
                        owner
                        repo
                        tag
                        ;
                    };

                    version = tag;
                  }
                ))
              ]
            else
              [ shadps4 ];
        }
      )
    ];

  meta.name = "shadps4";
}
