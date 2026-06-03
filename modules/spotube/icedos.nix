{ icedosLib, lib, ... }:

{
  options.icedos.applications.spotube =
    let
      inherit (icedosLib) mkBoolOption mkStrOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.spotube)
        nightly
        nightlyHash
        ;
    in
    {
      nightly = mkBoolOption { default = nightly; };
      nightlyHash = mkStrOption { default = nightlyHash; };
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

        let
          inherit (lib) optionals;
          inherit (config.icedos.applications.spotube) nightly nightlyHash;
        in
        {
          nixpkgs.overlays = optionals nightly [
            (final: prev: {
              spotube = prev.spotube.overrideAttrs (_: {
                version = "nightly";

                src = final.fetchurl {
                  url = "https://github.com/KRTirtho/spotube/releases/download/nightly/Spotube-linux-x86_64.deb";
                  hash = nightlyHash;
                };
              });
            })
          ];

          environment.systemPackages = [ pkgs.spotube ];
        }
      )
    ];

  meta.name = "spotube";
}
