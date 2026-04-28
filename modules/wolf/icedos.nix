{ lib, icedosLib, ... }:

{
  options.icedos.applications.wolf =
    let
      inherit (lib) mkOption readFile;
      inherit (icedosLib) mkStrOption mkStrListOption;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.wolf)
        extraEnvironmentFlags
        extraOptions
        extraPackages
        extraVolumes
        image
        stateFolder
        ;
    in
    {
      extraEnvironmentFlags = mkOption { default = extraEnvironmentFlags; };
      extraOptions = mkStrListOption { default = extraOptions; };
      extraPackages = mkStrListOption { default = extraPackages; };
      extraVolumes = mkStrListOption { default = extraVolumes; };
      image = mkStrOption { default = image; };
      stateFolder = mkStrOption { default = stateFolder; };
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
          inherit (config) icedos fileSystems;
          inherit (icedos.applications) wolf;

          inherit (lib)
            any
            attrNames
            concatStringsSep
            filter
            hasPrefix
            head
            removePrefix
            replaceStrings
            splitString
            ;

          inherit (wolf) extraVolumes stateFolder;

          # Dynamic mount dependencies based on configured volumes
          hostPaths = [ stateFolder ] ++ map (v: head (splitString ":" v)) extraVolumes;

          mountPoints = filter (mp: mp != "/" && any (hp: hasPrefix (mp + "/") hp || mp == hp) hostPaths) (
            attrNames fileSystems
          );

          # Convert filesystem path to systemd mount unit name
          # Hyphens in path components must be escaped as \x2d to match systemd's escaping
          pathToMountUnit =
            path:
            let
              components = splitString "/" (removePrefix "/" path);
              escaped = map (c: replaceStrings [ "-" ] [ "\\x2d" ] c) components;
            in
            "${concatStringsSep "-" escaped}.mount";

          requiredMounts = map pathToMountUnit mountPoints;
        in
        {
          virtualisation = {
            oci-containers =
              let
                inherit (wolf)
                  extraEnvironmentFlags
                  extraOptions
                  image
                  stateFolder
                  ;
              in
              {
                backend = "docker";

                containers.wolf = {
                  image = if image != "" then image else "ghcr.io/games-on-whales/wolf";

                  extraOptions = [
                    "--pull=always"
                    "--device-cgroup-rule=c 13:* rmw"
                    "--network=host"
                    "--device=/dev/dri"
                    "--device=/dev/uinput"
                    "--device=/dev/uhid"
                  ]
                  ++ extraOptions;

                  environment = {
                    HOST_APPS_STATE_FOLDER = stateFolder;
                    XDG_RUNTIME_DIR = "/tmp/sockets";
                  }
                  // extraEnvironmentFlags;

                  volumes = [
                    "${stateFolder}:${stateFolder}"
                    "/dev:/dev"
                    "/run/udev:/run/udev"
                    "/tmp/sockets:/tmp/sockets"
                    "/var/run/docker.sock:/var/run/docker.sock"
                  ];
                };
              };
          };

          systemd.services.docker-wolf.preStart =
            let
              inherit (builtins) attrNames readDir toJSON;
              inherit (icedosLib.users) getNormal;
              inherit (lib) concatStringsSep flatten makeBinPath;
              inherit (wolf) extraPackages extraVolumes stateFolder;

              defaultVolumes = [
                "/nix/store:/nix/store:ro"
                "/run/current-system/sw/bin:/host-apps/system:ro"
                "/run/opengl-driver:/run/opengl-driver:ro"
                "/var/run/wolf/wolf.sock:/var/run/wolf/wolf.sock"
              ];

              extraPackagesVolumes = flatten (
                map (
                  package:
                  map (binExe: "${pkgs.${package}}/bin/${binExe}:/host-apps/extra/${binExe}:ro") (
                    attrNames (readDir "${pkgs.${package}}/bin")
                  )
                ) extraPackages
              );

              userPackagesVolumes =
                map
                  (
                    user:
                    let
                      inherit (user) value name;
                      inherit (value) home;
                    in
                    "${home}/.nix-profile/bin:/host-apps/${name}:ro"
                  )
                  (getNormal {
                    inherit (config.users) users;
                  });

              volumes = defaultVolumes ++ extraPackagesVolumes ++ extraVolumes ++ userPackagesVolumes;
            in
            ''
              PATH=${
                with pkgs;
                makeBinPath [
                  toml-cli
                  jq
                ]
              }:$PATH

              # Wait for DNS to become available
              for i in $(seq 1 30); do
                getent hosts ghcr.io > /dev/null 2>&1 && break
                sleep 1
              done

              CONFIG="${stateFolder}/cfg/config.toml"
              PROFILES=$(toml get "$CONFIG" profiles | jq length)
              TMP_FOLDER="$(mktemp -d -t -p /tmp/icedos wolf-extra-volumes-XXXXXXX-0 | xargs echo)/"

              if [[ ! -e "$CONFIG" ]]; then
                touch "$CONFIG"
              fi

              cd "$TMP_FOLDER"
              cat "$CONFIG" > tmp

              for i in $(seq 0 $((PROFILES - 1))); do
                APPS=$(toml get "$CONFIG" profiles[$i].apps | jq length)

                for x in $(seq 0 $((APPS - 1))); do
                  toml set tmp profiles[$i].apps[$x].runner.mounts '[${concatStringsSep "," (map toJSON volumes)}]' > tmp2
                  sed -i 's/^\s*mounts = "\[\(.*\)\]"$/mounts = [\1]/; /^\s*mounts = / s/\\"/\"/g' tmp2
                  cp tmp2 tmp
                done
              done

              cat tmp > "$CONFIG"
              rm -rf "$TMP_FOLDER"
            '';

          systemd.services.docker-wolf.serviceConfig.RestartSec = 10;
          systemd.services.docker-wolf.after = [ "network-online.target" ] ++ requiredMounts;
          systemd.services.docker-wolf.wants = [ "network-online.target" ];
          systemd.services.docker-wolf.requires = requiredMounts;

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

  meta = {
    name = "wolf";

    dependencies = [
      {
        modules = [ "docker" ];
      }
    ];
  };
}
