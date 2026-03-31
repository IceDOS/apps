{ icedosLib, lib, ... }:

{
  options.icedos.applications.tailscale.enableTrayscale =
    let
      inherit ((fromTOML (lib.readFile ./config.toml)).icedos.applications.tailscale)
        enableTrayscale
        ;
    in
    icedosLib.mkBoolOption { default = enableTrayscale; };

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
          inherit (lib) optional;
          enableTrayscale = config.icedos.applications.tailscale.enableTrayscale;
        in
        {
          environment.systemPackages = with pkgs; [ tailscale ] ++ optional enableTrayscale trayscale;
          services.tailscale.enable = true;
        }
      )
    ];

  meta.name = "tailscale";
}
