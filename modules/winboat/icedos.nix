{ icedosLib, ... }:

{
  inputs.winboat = {
    url = "github:TibixDev/winboat";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  options.icedos.applications.winboat.autostart = icedosLib.mkBoolOption { default = false; };

  outputs.nixosModules =
    { inputs, ... }:
    [
      { environment.systemPackages = [ inputs.winboat.packages.x86_64-linux.winboat ]; }

      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          boot.kernelModules = [ "iptable_nat" ];

          environment.systemPackages = with pkgs; [
            freerdp3
            docker-compose
            iptables
          ];

          icedos.applications.toolset.commands = [
            (
              let
                command = "clear-winboat";
                docker = "${pkgs.docker}/bin/docker";
              in
              {
                bin = "${pkgs.writeShellScript command ''
                  ${docker} stop WinBoat
                  ${docker} rm WinBoat
                  ${docker} volume rm winboat_data
                  rm -rf ~/.winboat
                ''} 2> /dev/null";
                command = command;
                help = "purge all winboat files for a clean installation";
              }
            )
          ];

          systemd.services.docker.serviceConfig.ExecStartPost =
            let
              cfg = config.icedos;
              inherit (lib) mkIf;
              inherit (pkgs) docker;
            in
            mkIf (!cfg.applications.winboat.autostart) ''
              (${docker}/bin/docker stop WinBoat || exit 0)
            '';

          users.users = lib.mapAttrs (user: _: {
            extraGroups = [ "docker" ];
          }) config.icedos.users;

          virtualisation.docker.enable = true;
          virtualisation.libvirtd.enable = true;
        }
      )
    ];

  meta.name = "winboat";
}
