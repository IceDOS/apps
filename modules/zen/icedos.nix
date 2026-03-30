{ icedosLib, lib, ... }:

{
  options.icedos.applications.zen =
    let
      inherit (icedosLib)
        mkBoolOption
        mkStrListOption
        mkStrOption
        mkSubmoduleListOption
        ;

      inherit (lib) readFile;
      profileDefaults = fromTOML (readFile ./profiles.toml);
    in
    {

      profiles = mkSubmoduleListOption { default = [ ]; } {
        default = mkBoolOption { default = profileDefaults.default; };
        exec = mkStrOption { };
        icon = mkStrOption { default = profileDefaults.icon; };
        name = mkStrOption { default = profileDefaults.name; };
        privacy = mkBoolOption { default = profileDefaults.privacy; };
        pwa = mkBoolOption { default = profileDefaults.pwa; };
        sites = mkStrListOption { default = profileDefaults.sites; };
      };
    };

  inputs.zen = {
    url = "github:0xc000022070/zen-browser-flake";
    inputs.nixpkgs.follows = "nixpkgs";
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
        let
          inherit (config.icedos.applications) defaultBrowser;
          inherit (pkgs.stdenv.hostPlatform) system;
          inherit (inputs.zen.packages.${system}) default;
          inherit (lib) mkIf;
        in
        {
          environment = {
            sessionVariables.DEFAULT_BROWSER = mkIf (defaultBrowser == "zen.desktop") "${default}/bin/zen-beta";
            systemPackages = [ default ];
          };
        }
      )

      ./modules/profiles
      ./modules/user.js
    ];

  meta.name = "zen";
}
