{ icedosLib, lib, ... }:

{
  options.icedos.applications.spotube =
    let
      inherit (icedosLib) mkBoolOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.applications.spotube) git nightly;
    in
    {
      nightly = mkBoolOption { default = nightly; };
      git = mkBoolOption { default = git; };
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
          inherit (lib) optionals;
          inherit (config.icedos.applications.spotube) git nightly;
        in
        {
          assertions = [
            {
              assertion = !(git && nightly);
              message = "icedos.applications.spotube: enable either nightly or git, not both.";
            }
          ];

          # nightly repackages upstream's rolling nightly deb (source.json). git builds the
          # pinned dev commit (git.json) into a deb and runs it through the same repackage.
          nixpkgs.overlays =
            optionals (nightly || git) (import ./nightly.nix).nixpkgs.overlays
            ++ optionals git (import ./git.nix).nixpkgs.overlays;

          environment.systemPackages = [ pkgs.spotube ];
        }
      )
    ];

  meta.name = "spotube";
}
