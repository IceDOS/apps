{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        let
          base = pkgs.lsfg-vk;
        in
        {
          environment.systemPackages = with pkgs; [
            base
            lsfg-vk-ui
          ];

          environment.etc."vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json".source =
            "${base}/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json";
        }
      )
    ];

  meta = {
    name = "lsfg-vk";
    depends = [ ];
  };
}
