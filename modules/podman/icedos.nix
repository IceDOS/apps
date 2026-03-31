{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { ... }:
        {
          virtualisation.podman.enable = true;
        }
      )
    ];

  meta.name = "podman";
}
