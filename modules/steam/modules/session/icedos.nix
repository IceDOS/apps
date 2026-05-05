{ icedosLib, lib, ... }:

{
  options.icedos.applications.steam.session =
    let
      inherit (lib) readFile;
      inherit (icedosLib) mkStrListOption mkUntypedOption;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.steam.session)
        args
        env
        steamArgs
        ;
    in
    {
      args = mkStrListOption { default = args; };
      env = mkUntypedOption { default = env; };
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

  meta.name = "steam-session";
}
