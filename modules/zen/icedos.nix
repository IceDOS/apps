{ icedosLib, ... }:

{
  options.icedos.applications.zen =
    let
      inherit (icedosLib)
        mkBoolOption
        mkStrListOption
        mkStrOption
        mkSubmoduleListOption
        ;
    in
    {

      profiles = mkSubmoduleListOption { default = [ ]; } {
        default = mkBoolOption { default = false; };
        exec = mkStrOption { };
        icon = mkStrOption { default = ""; };
        name = mkStrOption { default = ""; };
        privacy = mkBoolOption { default = false; };
        pwa = mkBoolOption { default = false; };
        sites = mkStrListOption { default = [ ]; };
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
