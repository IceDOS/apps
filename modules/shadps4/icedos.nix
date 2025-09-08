{ icedosLib, ... }:

{

  options.icedos.applications.shadps4.customBuild =
    let
      inherit (icedosLib) mkBoolOption mkStrOption;
    in
    {
      enable = mkBoolOption { default = false; };
      hash = mkStrOption { default = "sha256-mxLv1IUHDQWUOvoapaueZO76+bCNsZK5IHuJ6rjF0aE="; };
      owner = mkStrOption { default = "shadps4-emu"; };
      repo = mkStrOption { default = "shadps4"; };
      tag = mkStrOption { default = "Pre-release-shadPS4-2025-09-08-133f4b9"; };
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
