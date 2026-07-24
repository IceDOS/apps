{ icedosLib, lib, ... }:

{
  options.icedos.applications.steam.session =
    let
      inherit (lib) importTOML types;
      inherit (icedosLib) mkAttrsOfOption mkStrListOption;

      inherit ((importTOML ./config.toml).icedos.applications.steam.session)
        args
        env
        steamArgs
        ;
    in
    {
      args = mkStrListOption { default = args; };
      env = mkAttrsOfOption { default = env; } types.str;
      steamArgs = mkStrListOption { default = steamArgs; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:
        {
          programs.steam.gamescopeSession = {
            inherit (config.icedos.applications.steam.session) args env steamArgs;
            enable = true;
          };
        }
      )
    ];

  meta = {
    name = "steam-session";
    dependencies = [ { modules = [ "steam" ]; } ];
  };
}
