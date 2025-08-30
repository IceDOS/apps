{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      {
        virtualisation = {
          oci-containers = {
            backend = "docker";

            containers.wolf = {
              image = "ghcr.io/games-on-whales/wolf:stable";

              extraOptions = [
                "--pull=always"
                "--device-cgroup-rule=c 13:* rmw"
                "--network=host"
                "--device=/dev/dri"
                "--device=/dev/uinput"
                "--device=/dev/uhid"
              ];

              environment = {
                XDG_RUNTIME_DIR = "/tmp/sockets";
                HOST_APPS_STATE_FOLDER = "/etc/wolf";
              };

              volumes = [
                "/etc/wolf/:/etc/wolf"
                "/tmp/sockets:/tmp/sockets:rw"
                "/var/run/docker.sock:/var/run/docker.sock:rw"
                "/dev/:/dev/:rw"
                "/run/udev:/run/udev:rw"
              ];
            };
          };
        };
      }
    ];

  meta.name = "wolf";
}
