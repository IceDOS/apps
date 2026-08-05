{ icedosLib, lib, ... }:

{
  options.icedos.applications.winboat =
    let
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.applications.winboat) autostart;
    in
    {
      autostart = icedosLib.mkBoolOption { default = autostart; };
    };

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
          inherit (lib) mkIf;
          inherit (config) icedos;
          inherit (icedos.applications.winboat) autostart;
          # Read defensively: the docker module is a dependency, but a
          # fetchDependencies=false repo layout can omit it — treat that as
          # absent (false / empty allowlist) rather than hard-failing eval.
          dockerEnabled = config.virtualisation.docker.enable or false;
        in
        {
          boot.kernelModules = [ "iptable_nat" ];

          assertions = [
            {
              assertion = dockerEnabled;
              message = "winboat requires the docker daemon, but icedos.virtualisation.docker is not enabled. Enable the virtualisation `docker` module (a declared dependency) or set virtualisation.docker.enable = true.";
            }
          ];

          environment.systemPackages = with pkgs; [
            freerdp
            docker-compose
            iptables
          ];

          icedos.system.toolset.commands =
            let
              docker = "${pkgs.docker}/bin/docker";
            in
            [
              {
                command = "clear-winboat";

                # The docker daemon is enabled (asserted above), but the docker
                # group is a privilegedUsers allowlist that defaults to empty —
                # so say so at the point the user actually runs the command,
                # not on every build. Printed BEFORE the stderr redirect below,
                # which would otherwise swallow it.
                script = ''
                  if ! groups | grep -qw docker; then
                    echo "NOTE: you are not in the docker group (icedos.virtualisation.docker.privilegedUsers is empty), so this needs sudo." >&2
                  fi
                  exec 2>/dev/null
                  ${docker} stop WinBoat
                  ${docker} rm WinBoat
                  ${docker} volume rm winboat_data
                  rm -rf ~/.winboat
                '';

                help = "purge all winboat files for a clean installation";
              }
            ];

          # Only touch the docker.service unit when the daemon actually exists.
          systemd.services.docker.serviceConfig.ExecStartPost =
            let
              inherit (pkgs) docker;
            in
            mkIf (dockerEnabled && !autostart) ''
              (${docker}/bin/docker stop WinBoat || exit 0)
            '';

          virtualisation.libvirtd.enable = true;
        }
      )
    ];

  meta = {
    name = "winboat";

    # The docker daemon + docker-group handling (icedos.virtualisation.docker.
    # privilegedUsers allowlist) live in the virtualisation `docker` module;
    # winboat only needs the daemon running for its containers.
    dependencies = [
      {
        url = "github:icedos/virtualisation";
        modules = [ "docker" ];
      }
    ];
  };
}
