{ icedosLib, lib, ... }:

{
  options.icedos.applications.spotube =
    let
      inherit (icedosLib) mkBoolOption;
      inherit (lib) readFile;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.spotube) nightly;
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
          # Upstream replaces one rolling `nightly` release in place, so the URL never
          # moves and only the hash does; update.sh / the update-spotube workflow keep
          # source.json fresh. The overlay lives in nightly.nix because the nightly is a
          # wholesale repackage rather than a version bump — see the note there.
          nixpkgs.overlays = mkIf nightly (import ./nightly.nix).nixpkgs.overlays;

          environment.systemPackages = [ pkgs.spotube ];
        }
      )
    ];

  meta.name = "spotube";
}
