{ icedosLib, lib, ... }:

{
  options.icedos.applications.power-profiles-daemon.profile =
    let
      inherit (icedosLib) mkStrOption;
      inherit (lib) readFile;
      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.power-profiles-daemon) profile;
    in
    mkStrOption { default = profile; };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          pkgs,
          ...
        }:

        let
          inherit (config) icedos;
          inherit (icedos.applications.power-profiles-daemon) profile;

          sessionTargets = icedosLib.systemd.desktopSessionTargets icedos;
        in
        {
          services.power-profiles-daemon.enable = true;

          home-manager.sharedModules = [
            {
              systemd.user.services.power-profiles-daemon-profile = {
                Unit = {
                  Description = "Power Profiles Daemon - Profile setter";

                  After = [ "graphical-session.target" ] ++ sessionTargets;
                  PartOf = "graphical-session.target";
                  StartLimitIntervalSec = 60;
                  StartLimitBurst = 60;
                };

                Install.WantedBy = sessionTargets;

                Service = {
                  ExecStart = "${pkgs.writeShellScriptBin "power-profiles-daemon-profile" ''
                    ${icedosLib.bash.exportSystemPath}

                    powerprofilesctl set ${profile}
                  ''}/bin/power-profiles-daemon-profile";

                  Nice = "-20";
                  Restart = "on-failure";
                };
              };
            }
          ];
        }
      )
    ];

  meta.name = "power-profiles-daemon";
}
