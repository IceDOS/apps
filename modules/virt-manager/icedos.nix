{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          ...
        }:

        let
          inherit (lib) hasAttr mapAttrs optional;
          inherit (config.icedos.hardware) cpus;
          cfg = config.icedos;
        in
        {
          programs.virt-manager.enable = true;

          virtualisation = {
            libvirtd.enable = true;
            spiceUSBRedirection.enable = true;
          };

          users.users = mapAttrs (user: _: {
            extraGroups = [ "libvirtd" ];
          }) cfg.users;

          boot.kernelParams = [
            # Allows passthrough of independent devices, that are members of larger IOMMU groups
            # It only affects kernels with ACS Override support. Ex: CachyOS, Liquorix, Zen
            "pcie_acs_override=downstream,multifunction"
          ]
          ++ optional (hasAttr "ryzen" cpus) "amd_iommu=on"
          ++ optional (hasAttr "intel" cpus) "intel_iommu=on";
        }
      )
    ];

  meta.name = "virt-manager";
}
