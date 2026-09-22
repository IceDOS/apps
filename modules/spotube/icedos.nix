{ icedosLib, lib, ... }:

{
  options.icedos.applications.spotube =
    let
      inherit (icedosLib) mkBoolOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.applications.spotube) nightly;
    in
    {
      nightly = mkBoolOption { default = nightly; };
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
          inherit (config.icedos.applications.spotube) nightly;
        in
        {
          # Upstream re-uploads one rolling nightly release: only the hash moves; update.sh
          # keeps source.json fresh. The repackage overlay lives in nightly.nix, not here.
          nixpkgs.overlays = mkIf nightly (import ./nightly.nix).nixpkgs.overlays;

          environment.systemPackages = [ pkgs.spotube ];
        }
      )
    ];

  meta.name = "spotube";
}
