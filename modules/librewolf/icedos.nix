{
  lib,
  icedosLib,
  ...
}:

{
  options.icedos.applications.defaultBrowser =
    let
      applications = (fromTOML (lib.fileContents ./config.toml)).icedos.applications;
    in
    icedosLib.mkStrOption { default = applications.defaultBrowser; };

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
          inherit (lib) mapAttrs mkIf;

          cfg = config.icedos;
          users = cfg.system.users;
          package = pkgs.librewolf;
        in
        {
          # Set as default browser for electron apps
          environment = {
            sessionVariables.DEFAULT_BROWSER = mkIf (
              cfg.applications.defaultBrowser == "librewolf.desktop"
            ) "${package}/bin/librewolf";

            systemPackages = [ package ];
          };

          home-manager.users = mapAttrs (user: _: {
            home.file = {
              ".librewolf/profiles.ini" = {
                text = ''
                  [Profile0]
                  Name=Default
                  IsRelative=1
                  Path=default
                  Default=1

                  [General]
                  StartWithLastProfile=1
                  Version=2
                '';

                force = true;
              };
            };

            programs.librewolf.settings =
              let
                firefoxVersion = lib.substring 0 5 pkgs.firefox.version;
              in
              {
                "browser.download.autohideButton" = true;
                "browser.theme.dark-private-windows" = false;
                "general.autoScroll" = true;
                "general.useragent.override" =
                  "Mozilla/5.0 (X11; Linux x86_64; rv:${firefoxVersion}) Gecko/20100101 Firefox/${firefoxVersion}";
                "identity.fxaccounts.enabled" = true;
                "image.jxl.enabled" = true; # Enable JPEG XL support
                "media.ffmpeg.vaapi.enabled" = true; # Enable VA-API hard accelaration
                "middlemouse.paste" = false;
                "privacy.resistFingerprinting" = false;
                "svg.context-properties.content.enabled" = true;
                "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
                "webgl.disabled" = false;
              };
          }) users;
        }
      )
    ];

  meta.name = "librewolf";
}
