{ icedosLib, lib, ... }:

{

  options.icedos.applications.shadps4 =
    let
      inherit (lib) importTOML;
      inherit ((importTOML ./config.toml).icedos.applications.shadps4) prerelease shadnet;
      inherit (icedosLib) mkBoolOption;
    in
    {
      # Rolling upstream prerelease — pinned by commit since tags get replaced.
      prerelease = mkBoolOption { default = prerelease; };

      # shadp2p fork: the forked shadPS4 core with the shadnet P2P client.
      # With a stable base it stands alone; with prerelease it merges the P2P
      # delta onto the prerelease base. Only one shadps4 bin is ever built.
      shadnet = mkBoolOption { default = shadnet; };
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
          inherit (config.icedos.applications.shadps4) prerelease shadnet;
          # When the shadnet-p2p server runs on this machine too, the client's
          # seamless mode must match the server's - a mismatch silently breaks co-op.
          p2p = config.icedos.applications.shadnet-p2p or null;
          localServer = p2p != null && ((p2p.enable or false) || (p2p.userService or false));
        in
        {
          assertions = [
            {
              assertion = !localServer || !shadnet || (p2p.seamless or false);
              message = "icedos.applications.shadps4: shadnet enables the seamless client, but the local shadnet-p2p server runs with seamless = false.";
            }
          ];
          environment.systemPackages = with pkgs; [
            shadps4
            shadps4-qtlauncher
          ];

          # The shadnet client only enables its seamless co-op hooks when this is
          # set, and it must match the server's BloodborneSeamlessCoop setting.
          environment.sessionVariables = lib.mkIf shadnet {
            SHADPS4_BLOODBORNE_SEAMLESS_COOP = "1";
          };

          # One composed shadps4 per option combination:
          #   prerelease=false, shadnet=false -> nixpkgs shadps4
          #   prerelease=true,  shadnet=false -> upstream prerelease base
          #   prerelease=false, shadnet=true  -> shadnet fork build
          #   prerelease=true,  shadnet=true  -> prerelease base + P2P delta (merge)
          nixpkgs.overlays =
            (lib.optionals prerelease (import ./prerelease.nix).nixpkgs.overlays)
            ++ (lib.optionals (shadnet && (!prerelease)) (import ./shadnet.nix).nixpkgs.overlays)
            ++ (lib.optionals (shadnet && prerelease) (import ./shadnet-merge.nix).nixpkgs.overlays);
        }
      )
    ];

  meta.name = "shadps4";
}
