{ icedosLib, lib, ... }:

{
  options.icedos.applications.zen =
    let
      inherit ((fromTOML (readFile ./profiles.toml)).icedos.applications.zen)
        profiles
        ;

      inherit (icedosLib)
        mkBoolOption
        mkStrListOption
        mkStrOption
        mkSubmoduleListOption
        ;

      inherit (lib) head readFile;
    in
    {

      profiles =
        let
          inherit (head profiles) default icon name privacy pwa sites;
        in
        mkSubmoduleListOption { default = [ ]; } {
          default = mkBoolOption { default = default; };
          exec = mkStrOption { };
          icon = mkStrOption { default = icon; };
          name = mkStrOption { default = name; };
          privacy = mkBoolOption { default = privacy; };
          pwa = mkBoolOption { default = pwa; };
          sites = mkStrListOption { default = sites; };
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
