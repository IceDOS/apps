{ lib, icedosLib, ... }:

{
  options.icedos.applications.opencode =
    let
      inherit (lib) readFile mkOption;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.opencode)
        extraSettings
        ;
    in
    {
      extraSettings = mkOption { default = extraSettings; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (lib) recursiveUpdate;
          inherit (config.icedos.applications.opencode) extraSettings;
        in
        {
          home-manager.sharedModules = [
            {
              programs.opencode = {
                enable = true;

                settings = recursiveUpdate {
                  "$schema" = "https://opencode.ai/config.json";

                  # Auto-allow skills discovered from ~/.claude/skills (Claude-compatible).
                  permission.skill."*" = "allow";
                } extraSettings;
              };
            }
          ];
        }
      )
    ];

  meta.name = "opencode";
}
