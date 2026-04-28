{ icedosLib, lib, ... }:

{
  options.icedos.applications.winboat.autostart =
    let
      inherit (lib) readFile;
      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.winboat) autostart;
    in
    icedosLib.mkBoolOption { default = autostart; };

  outputs.nixosModules =
    { ... }:

    [
      (
        { pkgs, ... }:

        {
          environment.systemPackages =
            let
              inherit (pkgs) winboat;
            in
            [ winboat ];
        }
      )

      (
        {
          config,
          lib,
          pkgs,
          ...
        }:

        let
          inherit (lib) mkIf mapAttrs;
        in
        {
          boot.kernelModules = [ "iptable_nat" ];

          environment.systemPackages = with pkgs; [
            freerdp
            docker-compose
            iptables
          ];

          icedos.applications.toolset.commands =
            let
              docker = "${pkgs.docker}/bin/docker";
            in
            [
              {
                command = "clear-winboat";

                script = ''
                  exec 2>/dev/null
                  ${docker} stop WinBoat
                  ${docker} rm WinBoat
                  ${docker} volume rm winboat_data
                  rm -rf ~/.winboat
                '';

                help = "purge all winboat files for a clean installation";
              }
            ];

          systemd.services.docker.serviceConfig.ExecStartPost =
            let
              cfg = config.icedos;
              inherit (pkgs) docker;
            in
            mkIf (!cfg.applications.winboat.autostart) ''
              (${docker}/bin/docker stop WinBoat || exit 0)
            '';

          users.users = mapAttrs (user: _: {
            extraGroups = [ "docker" ];
          }) config.icedos.users;

          virtualisation.docker.enable = true;
          virtualisation.libvirtd.enable = true;
        }
      )
    ];

  meta.name = "winboat";
}
