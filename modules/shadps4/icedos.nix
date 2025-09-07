{ icedosLib, ... }:

{

  options.icedos.applications.shadps4.customBuild =
    let
      inherit (icedosLib) mkBoolOption mkStrOption;
    in
    {
      enable = mkBoolOption { default = false; };
      hash = mkStrOption { default = "sha256-jLCWwNjRYneuYQg0hQVHuVW4e+rWaoYWj9kAOzwqdmw="; };
      owner = mkStrOption { default = "diegolix29"; };
      repo = mkStrOption { default = "shadps4"; };
      tag = mkStrOption { default = "BBFork-shadPS4-2025-09-07-9468c80"; };
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
                (
                  let
                    inherit (builtins) substring;
                  in
                  shadps4.overrideAttrs (
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

                      version = substring 26 33 tag;
                    }
                  )
                )
              ]
            else
              [ shadps4 ];
        }
      )
    ];

  meta.name = "shadps4";
}
