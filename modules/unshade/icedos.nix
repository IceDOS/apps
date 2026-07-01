{ icedosLib, lib, ... }:

{
  options.icedos.applications.unshade =
    let
      inherit (icedosLib) mkBoolOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.unshade)
        includeInIcedosGc
        ;
    in
    {
      includeInIcedosGc = mkBoolOption { default = includeInIcedosGc; };
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
          inherit (config.icedos.applications) unshade;
          inherit (lib) getExe mkIf;
        in
        {
          nixpkgs.overlays = [
            (final: super: {
              unshade = final.callPackage ./package.nix {
                inherit (icedosLib.packaging) installDesktopEntry;
              };
            })
          ];

          environment.systemPackages = [ pkgs.unshade ];

          # Append a non-interactive shader-cache sweep before nh clean.
          icedos.system.gc.hooks.postGc = mkIf unshade.includeInIcedosGc [
            "${getExe pkgs.unshade} --all"
          ];
        }
      )
    ];

  meta.name = "unshade";
}
