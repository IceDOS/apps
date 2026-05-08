{ icedosLib, ... }:

{
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
          users = config.icedos.users;
        in
        {
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
