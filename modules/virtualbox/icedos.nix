{ icedosLib, ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          ...
        }:
        let
          inherit (icedosLib.users) mkGroupInjector;
          users = config.icedos.users;
        in
        {
          virtualisation.virtualbox.host.enable = true;

          boot.kernelParams = [
            # Allow VirtualBox to run on kernel 6.13+
            "kvm.enable_virt_at_load=0"
          ];

          users.users = mkGroupInjector "vboxusers" users;
        }
      )
    ];

  meta.name = "virtualbox";
}
