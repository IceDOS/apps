{ icedosLib, lib, ... }:

{
  options.icedos = {
    applications =
      let
        inherit (icedosLib)
          mkBoolOption
          mkStrListOption
          mkStrOption
          mkSubmoduleListOption
          ;

        applications = (fromTOML (lib.fileContents ./config.toml)).icedos.applications;
      in
      {
        defaultBrowser = mkStrOption { default = applications.defaultBrowser; };

        zen = {
          privacy = mkBoolOption { default = false; };

          profiles = mkSubmoduleListOption { default = [ ]; } {
            default = mkBoolOption { };
            exec = mkStrOption { };
            icon = mkStrOption { };
            name = mkStrOption { };
            pwa = mkBoolOption { };
            sites = mkStrListOption { };
          };
        };
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
          inherit (lib) mkIf;

          cfg = config.icedos;
          package = inputs.zen.packages."${pkgs.system}".default;
        in
        {
          # Set as default browser for electron apps
          environment = {
            sessionVariables.DEFAULT_BROWSER = mkIf (
              cfg.applications.defaultBrowser == "zen.desktop"
            ) "${package}/bin/zen-beta";

            systemPackages = [ package ];
          };
        }
      )

      ./modules/profiles
      ./modules/user.js
    ];

  meta.name = "zen";
}
