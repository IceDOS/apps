{ icedosLib, ... }:

{
  options.icedos.applications.helium =
    let
      inherit (icedosLib)
        mkBoolOption
        mkStrListOption
        mkStrOption
        mkSubmoduleListOption
        ;
    in
    {
      drmSupportUsingGoogleChrome = mkBoolOption { default = false; };

      profiles = mkSubmoduleListOption { default = [ ]; } {
        exec = mkStrOption { };
        icon = mkStrOption { default = ""; };
        name = mkStrOption { default = ""; };
        sites = mkStrListOption { default = [ ]; };
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
          inherit (lib) length mapAttrs mkIf;

          package =
            if ((length profiles) == 0) then
              helium
            else
              pkgs.runCommand "helium" { } ''
                mkdir -p $out/bin

                echo "${helium}/bin/helium --profile-directory=Default \$@" > $out/bin/helium
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
