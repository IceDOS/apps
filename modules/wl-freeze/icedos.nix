{ icedosLib, lib, ... }:

{
  options.icedos.applications.wl-freeze =
    let
      inherit (icedosLib) mkBoolOption;

      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.applications.wl-freeze)
        hyprlandBind
        ;
    in
    {
      hyprlandBind = mkBoolOption { default = hyprlandBind; };
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
          inherit (config.icedos.applications) wl-freeze;
          inherit (lib) mkIf;

          hasHyprland = icedosLib.hasModule {
            inherit config;
            url = "github:icedos/hyprland";
            modules = [ "default" ];
          };
        in
        {
          nixpkgs.overlays = [
            (final: super: {
              wl-freeze = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.wl-freeze ];

          home-manager.sharedModules = [
            (mkIf (wl-freeze.hyprlandBind && hasHyprland) {
              wayland.windowManager.hyprland.settings.bind = [
                "$mainMod CTRL SHIFT, F, exec, wl-freeze -a"
              ];
            })
          ];
        }
      )
    ];

  meta.name = "wl-freeze";
}
