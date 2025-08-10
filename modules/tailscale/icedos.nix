{ icedosLib, ... }:

{
  options.icedos.applications.tailscale.enableTrayscale = icedosLib.mkBoolOption { default = false; };

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
