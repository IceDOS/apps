{ icedosLib, lib, ... }:

{
  options.icedos.applications.container-manager =
    let
      inherit (icedosLib) mkBoolOption;
      container-manager =
        (fromTOML (lib.fileContents ./config.toml)).icedos.applications.container-manager;
    in
    {
      usePodman = mkBoolOption { default = container-manager.usePodman; };
      requireSudoForDocker = mkBoolOption { default = container-manager.requireSudoForDocker; };
    };

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
          inherit (lib) mapAttrs mkIf;
          cfg = config.icedos;
        in
        {
          environment.systemPackages = with pkgs; [ distrobox ];
          virtualisation.docker.enable = !cfg.applications.container-manager.usePodman;
          virtualisation.podman.enable = cfg.applications.container-manager.usePodman;

          users.users = mapAttrs (user: _: {
            extraGroups =
              mkIf
                (
                  !cfg.applications.container-manager.usePodman
                  && !cfg.applications.container-manager.requireSudoForDocker
                )
                [
                  "docker"
                ];
          }) cfg.system.users;
        }
      )
    ];

  meta.name = "container-manager";
}
