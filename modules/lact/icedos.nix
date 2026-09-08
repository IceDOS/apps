{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        services.lact.enable = true;

        icedos.system.tips.list = [
          "LACT tunes your graphics card's fan curve, clocks and power limit from a window."
        ];
      }
    ];

  meta.name = "lact";
}
