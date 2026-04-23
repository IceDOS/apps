{ icedosLib, lib, ... }:

{
  options.icedos.applications.librewolf.bin =
    let
      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.librewolf) bin;
      inherit (icedosLib) mkBoolOption;
      inherit (lib) readFile;
    in
    mkBoolOption { default = bin; };

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
          inherit (config.icedos) applications users;
          inherit (applications) defaultBrowser;
          inherit (applications.librewolf) bin;
          inherit (lib) mapAttrs mkIf substring;
          inherit (pkgs) librewolf librewolf-bin;
          package = if bin then librewolf-bin else librewolf;
          stylixOn = config.stylix.enable or false;
        in
        {
          environment.sessionVariables.DEFAULT_BROWSER = mkIf (
            defaultBrowser == "librewolf.desktop"
          ) "${package}/bin/librewolf";

          home-manager.users = mapAttrs (user: _: {
            programs.librewolf = {
              enable = true;
              inherit package;
              profileVersion = 2;

              profiles.default = {
                id = 0;
                name = "Default";
                isDefault = true;
                path = "default";
              };

              settings =
                let
                  firefoxVersion = substring 1 5 (if bin then librewolf-bin.version else librewolf.version);
                in
                {
                  "browser.download.autohideButton" = true;
                  "browser.theme.dark-private-windows" = false;
                  "general.autoScroll" = true;
                  "general.useragent.override" =
                    "Mozilla/5.0 (X11; Linux x86_64; rv:${firefoxVersion}) Gecko/20100101 Firefox/${firefoxVersion}";
                  "identity.fxaccounts.enabled" = true;
                  "image.jxl.enabled" = true; # Enable JPEG XL support
                  "media.ffmpeg.vaapi.enabled" = true; # Enable VA-API hardware acceleration
                  "middlemouse.paste" = false;
                  "privacy.resistFingerprinting" = false;
                  "svg.context-properties.content.enabled" = true;
                  "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
                  "webgl.disabled" = false;
                };
            };

            stylix.targets.librewolf.profileNames = mkIf stylixOn [ "default" ];
          }) users;
        }
      )
    ];

  meta.name = "librewolf";
}
