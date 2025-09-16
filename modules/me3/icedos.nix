{ icedosLib, ... }:

{
  options.icedos.applications.me3.profiles = icedosLib.mkSubmoduleListOption { default = [ ]; } {
    config = icedosLib.mkStrOption { default = ""; };
    name = icedosLib.mkStrOption { default = ""; };
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
        {
          nixpkgs.overlays = [
            (final: super: {
              me3 = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages =
            let
              inherit (pkgs) me3;
            in
            [
              me3
            ];

          home-manager.users =
            let
              inherit (lib) listToAttrs mapAttrs;
              cfg = config.icedos;
            in
            mapAttrs (user: _: {
              home.file =
                let
                  inherit (builtins) foldl';
                  inherit (pkgs) me3;
                  homeWindowsBinPath = ".local/share/me3/windows-bin";
                  windowsBinPath = "${me3}/share/me3/windows-bin";
                in
                {
                  "${homeWindowsBinPath}/me3-launcher.exe".source = "${windowsBinPath}/me3-launcher.exe";
                  "${homeWindowsBinPath}/me3_mod_host.dll".source = "${windowsBinPath}/me3_mod_host.dll";
                }
                // foldl' (acc: atrrset: acc // atrrset) { } (
                  map (profile: {
                    ".config/me3/profiles/${profile.name}.me3".text = profile.config;
                  }) cfg.applications.me3.profiles
                );
            }) (listToAttrs (icedosLib.getNormalUsers { inherit (config.users) users; }));
        }
      )
    ];

  meta.name = "me3";
}
