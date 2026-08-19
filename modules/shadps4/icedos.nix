{ icedosLib, lib, ... }:

{

  options.icedos.applications.shadps4 =
    let
      inherit (lib) importTOML;
      inherit ((importTOML ./config.toml).icedos.applications.shadps4) prerelease;
      inherit (icedosLib) mkBoolOption;
    in
    {
      prerelease = mkBoolOption { default = prerelease; };
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
          inherit (lib) mkIf;
          inherit (config.icedos.applications.shadps4) prerelease;
        in
        {
          environment.systemPackages = with pkgs; [
            shadps4
            shadps4-qtlauncher
          ];

          # Rolling prerelease — pinned by commit since tags get replaced.
          nixpkgs.overlays = mkIf prerelease (import ./prerelease.nix).nixpkgs.overlays;
        }
      )
    ];

  meta.name = "shadps4";
}
