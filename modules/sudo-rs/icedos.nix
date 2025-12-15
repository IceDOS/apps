{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        security.sudo-rs = {
          enable = true;
          execWheelOnly = true;
          extraConfig = "Defaults pwfeedback";
        };
      }
    ];

  meta.name = "sudo-rs";
}
