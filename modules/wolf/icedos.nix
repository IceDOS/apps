{ icedosLib, ... }:

{
  options.icedos.applications.wolf.stateFolder = icedosLib.mkStrOption { default = "/etc/wolf"; };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, ... }:
        {
          virtualisation = {
            oci-containers =
              let
                stateFolder = config.icedos.applications.wolf.stateFolder;
              in
              {
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
                    HOST_APPS_STATE_FOLDER = stateFolder;
                  };

                  volumes = [
                    "${stateFolder}:${stateFolder}"
                    "/tmp/sockets:/tmp/sockets:rw"
                    "/var/run/docker.sock:/var/run/docker.sock:rw"
                    "/dev/:/dev/:rw"
                    "/run/udev:/run/udev:rw"
                  ];
                };
              };
          };
        }
      )
    ];

  meta.name = "wolf";
}
