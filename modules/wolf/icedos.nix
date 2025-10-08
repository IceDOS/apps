{ lib, icedosLib, ... }:

let
  defaultStateFolder = "/etc/wolf";
in
{
  options.icedos.applications.wolf =
    let
      inherit (lib) mkOption;
      inherit (icedosLib) mkStrOption mkStrListOption;
    in
    {
      extraEnvironmentFlags = mkOption { default = { }; };
      extraOptions = mkStrListOption { default = [ ]; };
      extraPackages = mkStrListOption { default = [ ]; };
      extraVolumes = mkStrListOption { default = [ ]; };
      stateFolder = mkStrOption { default = defaultStateFolder; };
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
          wolf = config.icedos.applications.wolf;
        in
        {
          virtualisation = {
            oci-containers =
              let
                inherit (lib) optional;
                inherit (wolf) stateFolder;
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
                  ]
                  ++ wolf.extraOptions;

                  environment = {
                    HOST_APPS_STATE_FOLDER = stateFolder;
                    XDG_RUNTIME_DIR = "/tmp/sockets";
                  }
                  // wolf.extraEnvironmentFlags;

                  volumes = [
                    "/dev:/dev"
                    "/etc/wolf:/etc/wolf"
                    "/run/udev:/run/udev"
                    "/tmp/sockets:/tmp/sockets"
                    "/var/run/docker.sock:/var/run/docker.sock"
                  ]
                  ++ optional (stateFolder != defaultStateFolder) "${stateFolder}:${stateFolder}";
                };
              };
          };

          systemd.services.docker-wolf.preStart =
            let
              inherit (builtins) attrNames toJSON readDir;
              inherit (lib) concatStringsSep flatten;
              inherit (pkgs) jq toml-cli;
              inherit (wolf) extraPackages extraVolumes;

              defaultVolumes = [
                "/nix/store:/nix/store:ro"
                "/run/current-system/sw/bin:/host-apps/system:ro"
                "/run/opengl-driver:/run/opengl-driver:ro"
              ];

              extraPackagesVolumes = flatten (
                map (
                  package:
                  map (binExe: "${pkgs.${package}}/bin/${binExe}:/host-apps/extra/${binExe}:ro") (
                    attrNames (readDir "${pkgs.${package}}/bin")
                  )
                ) extraPackages
              );

              jqBin = "${jq}/bin/jq";
              tomlBin = "${toml-cli}/bin/toml";

              userPackagesVolumes = map (user: "${user.value.home}/.nix-profile/bin:/host-apps/${user.name}:ro") (
                icedosLib.getNormalUsers { inherit (config.users) users; }
              );

              volumes = defaultVolumes ++ extraPackagesVolumes ++ extraVolumes ++ userPackagesVolumes;
            in
            ''
              CONFIG="/etc/wolf/cfg/config.toml"

              APPS=$(${tomlBin} get "$CONFIG" apps | ${jqBin} length)
              TMP_FOLDER="$(mktemp -d -t -p /tmp/icedos wolf-extra-volumes-XXXXXXX-0 | xargs echo)/"

              if [[ ! -e "$CONFIG" ]]; then
                touch "$CONFIG"
              fi

              cd "$TMP_FOLDER"
              cat "$CONFIG" > tmp

              for i in $(seq 0 $((APPS - 1))); do
                ${tomlBin} set tmp apps[$i].runner.mounts '[${concatStringsSep "," (map toJSON volumes)}]' > tmp2
                sed -i 's/^\s*mounts = "\[\(.*\)\]"$/mounts = [\1]/; /^\s*mounts = / s/\\"/\"/g' tmp2
                cp tmp2 tmp
              done

              cat tmp > "$CONFIG"
              rm -rf "$TMP_FOLDER"
            '';

          services.udev.extraRules = ''
            # Moonlight / NVIDIA GameStream virtual Xbox controller
            SUBSYSTEMS=="input", \
            ATTRS{name}=="Wolf X-Box One (virtual) pad", \
            MODE="0660", \
            ENV{ID_SEAT}="seat9", \
            GROUP="root"
          '';
        }
      )
    ];

  meta.name = "wolf";
}
