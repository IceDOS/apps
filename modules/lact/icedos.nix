{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        services.lact.enable = true;
      }
    ];

  meta.name = "lact";
}
