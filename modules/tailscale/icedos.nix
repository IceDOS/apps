{ icedosLib, lib, ... }:

{
  options.icedos.applications.tailscale.enableTrayscale =
    let
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.applications.tailscale)
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
          inherit (config.icedos.applications.tailscale) enableTrayscale;
        in
        {
          environment.systemPackages = with pkgs; [ tailscale ] ++ optional enableTrayscale trayscale;
          services.tailscale.enable = true;

          icedos.system.tips.list = lib.optionals enableTrayscale [
            "Trayscale sits in your system tray to connect and disconnect Tailscale."
          ];
        }
      )
    ];

  meta.name = "tailscale";
}
