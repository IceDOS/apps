{ icedosLib, lib, ... }:

{
  inputs.nix-flatpak.url = "github:gmodena/nix-flatpak/";

  options.icedos.applications.flatpak.packages =
    let
      inherit (lib) readFile;
      inherit (icedosLib) mkStrListOption;
      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.flatpak) packages;
    in
    mkStrListOption { default = packages; };

  outputs.nixosModules =
    { inputs, ... }:
    [
      (
        {
          config,
          lib,
          ...
        }:
        let
          inherit (config.icedos) applications users;
          inherit (applications.flatpak) packages;

          inherit (lib)
            elemAt
            length
            mapAttrs
            mkOptionDefault
            splitString
            ;
        in
        {
          services.flatpak.enable = true;

          home-manager.users = mapAttrs (user: _: {
            imports = [ inputs.nix-flatpak.homeManagerModules.nix-flatpak ];

            services.flatpak = {
              packages = map (
                package:
                let
                  packageParts = splitString ":" package;

                  package' =
                    if (length packageParts > 1) then
                      {
                        appId = elemAt packageParts 1;
                        origin = elemAt packageParts 0;
                      }
                    else
                      {
                        appId = package;
                        origin = "flathub";
                      };
                in
                package'
              ) packages;

              remotes = mkOptionDefault [
                {
                  name = "flathub-beta";
                  location = "https://flathub.org/beta-repo/flathub-beta.flatpakrepo";
                }
              ];
            };
          }) users;
        }
      )
    ];

  meta.name = "flatpak";
}
