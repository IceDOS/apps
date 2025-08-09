{ icedosLib, ... }:

{
  options.icedos = {
    applications.zen =
      let
        inherit (icedosLib)
          mkBoolOption
          mkStrListOption
          mkStrOption
          mkSubmoduleListOption
          ;
      in
      {
        privacy = mkBoolOption;

        profiles = mkSubmoduleListOption {
          default = mkBoolOption;
          exec = mkStrOption;
          icon = mkStrOption;
          name = mkStrOption;
          pwa = mkBoolOption;
          sites = mkStrListOption;
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
