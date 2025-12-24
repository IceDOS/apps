{ icedosLib, ... }:

{
  options.icedos.applications.helium =
    let
      inherit (icedosLib)
        mkStrListOption
        mkStrOption
        mkSubmoduleListOption
        ;
    in
    {
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
          inherit (config.icedos) applications;
          inherit (applications) defaultBrowser;
          inherit (applications.helium) profiles;
          inherit (pkgs.nur.repos.Ev357) helium;
          inherit (lib) length mkIf;

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
                  icon = profile.icon;
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
