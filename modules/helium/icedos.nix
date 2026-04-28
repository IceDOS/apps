{ icedosLib, lib, ... }:

{
  options.icedos.applications.helium =
    let
      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.helium)
        drmSupportUsingGoogleChrome
        ;

      inherit ((fromTOML (readFile ./profiles.toml)).icedos.applications.helium)
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
      drmSupportUsingGoogleChrome = mkBoolOption { default = drmSupportUsingGoogleChrome; };

      profiles =
        let
          inherit (head profiles) icon name sites;
        in
        mkSubmoduleListOption { default = [ ]; } {
          exec = mkStrOption { };
          icon = mkStrOption { default = icon; };
          name = mkStrOption { default = name; };
          sites = mkStrListOption { default = sites; };
        };
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
          inherit (config.icedos) applications;
          inherit (applications) defaultBrowser;
          inherit (applications.helium) drmSupportUsingGoogleChrome profiles;
          inherit (pkgs) google-chrome nur;
          inherit (nur.repos.Ev357) helium;

          inherit (lib)
            concatStringsSep
            length
            mkIf
            optional
            optionals
            ;

          flags = concatStringsSep " " (
            [ "--enable-features=AcceleratedVideoEncoder" ]
            ++ optional ((length profiles) != 0) "--profile-directory=Default"
          );

          package = pkgs.runCommand "helium" { } ''
            mkdir -p $out/bin

            echo '#!/bin/sh' > $out/bin/helium
            echo "${helium}/bin/helium ${flags} \"\$@\"" >> $out/bin/helium
            chmod +x $out/bin/helium

            ln -s ${helium}/share $out
          '';
        in
        {
          environment = {
            sessionVariables.DEFAULT_BROWSER = mkIf (
              defaultBrowser == "helium.desktop"
            ) "${package}/bin/helium";

            systemPackages = [ package ];
          };

          # CJK fonts are needed until this issue is fixed https://github.com/NixOS/nixpkgs/issues/463615
          fonts.packages = with pkgs; [
            noto-fonts-cjk-sans
            noto-fonts-cjk-serif
          ];

          home-manager.sharedModules = optionals drmSupportUsingGoogleChrome [
            {
              home.file = {
                ".config/net.imput.helium/WidevineCdm/latest-component-updated-widevine-cdm".text =
                  ''{"Path":"${google-chrome}/share/google/chrome/WidevineCdm"}'';
              };
            }
          ];
        }
      )

      # Profiles
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:

        let
          inherit (lib) listToAttrs;
          inherit (config.icedos.applications.helium) profiles;
          inherit (pkgs.nur.repos.Ev357) helium;
        in
        {
          environment.systemPackages = map (
            profile:
            pkgs.writeShellScriptBin profile.exec ''
              helium --profile-directory="${profile.exec}" ${toString profile.sites}
            ''
          ) profiles;

          home-manager.sharedModules = [
            {
              xdg.desktopEntries = listToAttrs (
                map (profile: {
                  name = profile.exec;

                  value = {
                    exec = profile.exec;

                    icon =
                      if (profile.icon == "") then
                        "${helium}/share/icons/hicolor/256x256/apps/helium.png"
                      else
                        profile.icon;

                    name = profile.name;
                    terminal = false;
                    type = "Application";
                  };
                }) profiles
              );
            }
          ];
        }
      )
    ];

  meta = {
    name = "helium";

    dependencies = [
      {
        url = "github:icedos/providers";
        modules = [ "nur" ];
      }
    ];
  };
}
