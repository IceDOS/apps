{ ... }:

{
  outputs.nixosModules = { ... }: [ { virtualisation.waydroid.enable = true; } ];
  meta.name = "waydroid";
}
