{ icedosLib, lib, ... }:

{

  options.icedos.applications.shadps4 =
    let
      inherit (lib) readFile;
      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.shadps4) prerelease;
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

          # Upstream ships a single rolling prerelease and replaces it in place, so the
          # pin is a commit (tags disappear) and update.sh / the update-shadps4 workflow
          # keep prerelease.json fresh. The overlay lives in prerelease.nix because
          # update.sh evaluates it too — the pin hash depends on how it fetches.
          nixpkgs.overlays = mkIf prerelease (import ./prerelease.nix).nixpkgs.overlays;
        }
      )
    ];

  meta.name = "shadps4";
}
