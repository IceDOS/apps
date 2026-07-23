{ lib, ... }:

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
    { inputs, ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (lib) recursiveUpdate;
          inherit (config.icedos.applications.opencode) extraSettings skills;

          peonPingUsers = config.icedos.applications.peon-ping.users or { };
          peonPingEnabled = peonPingUsers != { };
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

            (
              { lib, pkgs, ... }:

              lib.mkIf peonPingEnabled {
                # Upstream plugin writes an OSC set-title escape to stdout with no
                # TTY guard. Harmless in the TUI, but under Zed's ACP mode opencode's
                # stdout is the JSON-RPC pipe, so the escape corrupts the stream and
                # Zed hangs at "loading…". Guard the write on an interactive TTY.
                xdg.configFile."opencode/plugins/peon-ping.ts".source =
                  pkgs.runCommand "peon-ping-opencode.ts" { }
                    ''
                      substitute ${inputs.peon-ping}/adapters/opencode/peon-ping.ts "$out" \
                        --replace-fail \
                          'process.stdout.write(`\x1b]0;' \
                          'if (process.stdout.isTTY) process.stdout.write(`\x1b]0;'
                    '';
              }
            )
          ];
        }
      )
    ];

  meta.name = "opencode";
}
