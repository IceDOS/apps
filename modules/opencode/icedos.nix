{ lib, icedosLib, ... }:

{
  options.icedos.applications.opencode =
    let
      inherit (lib) readFile mkOption;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.opencode)
        extraSettings
        skills
        ;
    in
    {
      extraSettings = mkOption { default = extraSettings; };
      skills = mkOption { default = skills; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (lib) recursiveUpdate;
          inherit (config.icedos.applications.opencode) extraSettings skills;
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

                skills = skills;
              };
            }
          ];
        }
      )
    ];

  meta.name = "opencode";
}
