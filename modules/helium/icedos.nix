{ icedosLib, lib, ... }:

{
  options.icedos.applications.helium =
    let
      inherit ((fromTOML (lib.fileContents ./config.toml)).icedos.applications.helium)
        drmSupportUsingGoogleChrome
        profiles
        ;

      inherit (icedosLib)
        mkBoolOption
        mkStrListOption
        mkStrOption
        mkSubmoduleListOption
        ;

      inherit (lib) elemAt;

      profileDefaults = elemAt 0 profiles;
    in
    {
      drmSupportUsingGoogleChrome = mkBoolOption { default = drmSupportUsingGoogleChrome; };

      profiles = mkSubmoduleListOption { default = [ ]; } {
        exec = mkStrOption { };
        icon = mkStrOption { default = profileDefaults.icon; };
        name = mkStrOption { default = profileDefaults.name; };
        sites = mkStrListOption { default = profileDefaults.sites; };
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
          inherit (config.icedos) applications users;
          inherit (applications) defaultBrowser;
          inherit (applications.helium) drmSupportUsingGoogleChrome profiles;
          inherit (pkgs) google-chrome nur;
          inherit (nur.repos.Ev357) helium;

          inherit (lib)
            concatStringsSep
            length
            mapAttrs
            mkIf
            optional
            ;

          flags = concatStringsSep " " (
            [ "--enable-features=AcceleratedVideoEncoder" ]
            ++ optional ((length profiles) != 0) "--profile-directory=Default"
          );

          package = pkgs.runCommand "helium" { } ''
            mkdir -p $out/bin

            echo '#!/bin/sh' > $out/bin/helium
            echo "${helium}/bin/helium ${flags} \$@" >> $out/bin/helium
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

          home-manager.users = mkIf drmSupportUsingGoogleChrome (
            mapAttrs (user: _: {
              home.file = {
                ".config/net.imput.helium/WidevineCdm/latest-component-updated-widevine-cdm".text =
                  ''{"Path":"${google-chrome}/share/google/chrome/WidevineCdm"}'';
              };
            }) users
          );
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
          inherit (lib)
            listToAttrs
            mapAttrs
            ;

          inherit (config.icedos) applications users;
          inherit (applications.helium) profiles;
          inherit (pkgs.nur.repos.Ev357) helium;
        in
        {
          environment.systemPackages = map (
            profile:
            pkgs.writeShellScriptBin profile.exec ''
              helium --profile-directory="${profile.exec}" ${toString profile.sites}
            ''
          ) profiles;

          home-manager.users = mapAttrs (user: _: {
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
          }) users;
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
