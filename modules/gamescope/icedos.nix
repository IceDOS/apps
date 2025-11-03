{ icedosLib, ... }:

{
  options.icedos.applications.gamescope = icedosLib.mkBoolOption { default = true; };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          pkgs,
          ...
        }:

        {
          environment.systemPackages = [ pkgs.gamescope ];
        }
      )
    ];

  meta.name = "gamescope";
}
