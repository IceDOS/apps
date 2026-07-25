{ icedosLib, ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          pkgs,
          ...
        }:
        {
          nixpkgs.overlays = [
            (final: super: {
              ubports-installer = final.callPackage ./package.nix {
                inherit (icedosLib.packaging) extractAppImage installDesktopEntry;
              };
            })
          ];

          environment.systemPackages = with pkgs; [
            ubports-installer
          ];

          services.udev.extraRules = ''
            # UBports Installer USB device rules for Android/Ubuntu Touch devices
            SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"
            SUBSYSTEM=="usb", ATTR{idVendor}=="0525", MODE="0666", GROUP="plugdev"
            SUBSYSTEM=="usb", ATTR{idVendor}=="2c37", MODE="0666", GROUP="plugdev"
          '';
        }
      )
    ];

  meta.name = "ubports-installer";
}
