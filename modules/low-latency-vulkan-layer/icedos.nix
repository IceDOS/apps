{ icedosLib, ... }:

{
  options.icedos.applications.low-latency-vulkan-layer = icedosLib.mkBoolOption { default = true; };

  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        let
          base = pkgs.low-latency-vulkan-layer;
        in
        {
          nixpkgs.overlays = [
            (final: super: {
              low-latency-vulkan-layer = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ base ];

          environment.etc."vulkan/implicit_layer.d/low_latency_layer.json".source =
            "${base}/share/vulkan/implicit_layer.d/low_latency_layer.json";

          environment.sessionVariables = {
            VK_LOADER_LAYERS_DISABLE = "VK_LAYER_MESA_anti_lag";
            DISABLE_LOW_LATENCY_LAYER = "1";
          };
        }
      )
    ];

  meta.name = "low-latency-vulkan-layer";
}
