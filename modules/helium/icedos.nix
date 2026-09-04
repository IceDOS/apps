{ icedosLib, lib, ... }:

{
  options.icedos.applications.helium =
    let
      inherit ((importTOML ./config.toml).icedos.applications.helium)
        drmSupportUsingGoogleChrome
        ;

      inherit ((importTOML ./profiles.toml).icedos.applications.helium)
        profiles
        ;

      inherit (icedosLib)
        mkBoolOption
        mkStrListOption
        mkStrOption
        mkSubmoduleListOption
        ;

      inherit (lib) head importTOML;
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
    { inputs, ... }:
    [
      inputs.nur.modules.nixos.default

      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          inherit (config.icedos) applications desktop;
          inherit (applications.helium) drmSupportUsingGoogleChrome;
          inherit (pkgs) google-chrome nur;
          inherit (nur.repos.lonerOrz) helium;

          inherit (lib)
            mkIf
            optionals
            ;

          wrapperScript = pkgs.writeShellScriptBin "helium-wrapper" ''
            case " $* " in
              *" --profile-directory"*) ;;
              *) set -- --profile-directory=Default "$@" ;;
            esac
            # Chromium keeps only the last --enable-features occurrence, so a
            # caller-supplied list would silently drop ours. Merge into theirs.
            features=AcceleratedVideoEncoder
            merged=0

            for arg do
              shift
              case "$arg" in
                --enable-features=*)
                  arg="$arg,$features"
                  merged=1
                  ;;
              esac
              set -- "$@" "$arg"
            done

            [ "$merged" -eq 1 ] || set -- --enable-features="$features" "$@"

            exec ${helium}/bin/helium "$@"
          '';

          package = pkgs.symlinkJoin {
            name = "helium";
            paths = [ helium ];
            postBuild = ''
              rm -rf $out/bin
              mkdir -p $out/bin
              for f in ${helium}/bin/*; do
                ln -s "$f" "$out/bin/$(basename "$f")"
              done
              rm -f $out/bin/helium
              ln -s ${wrapperScript}/bin/helium-wrapper $out/bin/helium

              desktop="$out/share/applications/helium.desktop"
              if [ -f "$desktop" ] && [ -s "$desktop" ]; then
                rm -f "$desktop"
                cp "${helium}/share/applications/helium.desktop" "$desktop"
                substituteInPlace "$desktop" \
                  --replace-fail "Exec=helium" "Exec=$out/bin/helium"
              fi
            '';
          };
        in
        {
          environment = {
            sessionVariables.DEFAULT_BROWSER = mkIf (
              desktop.applications.browser.name == "helium.desktop"
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
              xdg.configFile = {
                "net.imput.helium/WidevineCdm/latest-component-updated-widevine-cdm".text =
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
          inherit (lib) concatStringsSep escapeShellArg listToAttrs;
          inherit (config.icedos.applications.helium) profiles;
          inherit (pkgs.nur.repos.lonerOrz) helium;
        in
        {
          environment.systemPackages = map (
            profile:
            pkgs.writeShellScriptBin profile.exec ''
              helium --profile-directory=${escapeShellArg profile.exec} \
                ${concatStringsSep " " (map escapeShellArg profile.sites)} "$@"
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
