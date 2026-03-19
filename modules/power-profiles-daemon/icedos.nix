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
          lib,
          pkgs,
          ...
        }:

        let
          cfg = config.icedos;
          inherit (cfg) applications users;
          inherit (applications.power-profiles-daemon) profile;
          inherit (lib) hasAttr mapAttrs optional;

          generateTargetArray =
            base:
            base
            ++ optional (hasAttr "desktop" cfg && hasAttr "cosmic" cfg.desktop) "cosmic-session.target"
            ++ optional (hasAttr "desktop" cfg && hasAttr "gnome" cfg.desktop) "gnome-session.target"
            ++ optional (hasAttr "desktop" cfg && hasAttr "hyprland" cfg.desktop) "hyprland-session.target";
        in
        {
          services.power-profiles-daemon.enable = true;

          home-manager.users = mapAttrs (user: _: {
            systemd.user.services.power-profiles-daemon-profile = {
              Unit = {
                Description = "Power Profiles Daemon - Profile setter";

                After = generateTargetArray [ "graphical-session.target" ];
                PartOf = "graphical-session.target";
              };

              Install.WantedBy = generateTargetArray [ ];

              Service = {
                ExecStart = "${pkgs.writeShellScriptBin "power-profiles-daemon-profile" ''
                  base_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                  nix_system_path="/run/current-system/sw/bin"
                  nix_user_path="''${HOME}/.nix-profile/bin"
                  export PATH="''${base_path}:''${nix_system_path}:''${nix_user_path}:$PATH"

                  powerprofilesctl set ${profile}
                ''}/bin/power-profiles-daemon-profile";

                Nice = "-20";
                Restart = "on-failure";
                StartLimitBurst = 60;
              };
            };
          }) users;
        }
      )
    ];

  meta.name = "power-profiles-daemon";
}
