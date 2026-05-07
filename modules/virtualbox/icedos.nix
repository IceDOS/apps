{ icedosLib, ... }:

{
  inputs = {
    nixos-unstable-small.url = "github:NixOS/nixpkgs/nixos-unstable-small";
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          inherit (lib) mapAttrs;

          small = import inputs.nixos-unstable-small {
            inherit (pkgs.stdenv) system;
            config = config.nixpkgs.config;
          };

          users = config.icedos.users;
        in
        {
          nixpkgs.overlays = [
            (self: super: { inherit (small) virtualbox; })
          ];

          virtualisation.virtualbox.host.enable = true;

          boot.kernelParams = [
            # Allow VirtualBox to run on kernel 6.13+
            "kvm.enable_virt_at_load=0"
          ];

          users.users = mapAttrs (user: _: { extraGroups = [ "vboxusers" ]; }) users;
        }
      )
    ];

  meta.name = "virtualbox";
}
