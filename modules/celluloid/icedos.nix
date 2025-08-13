{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          pkgs,
          lib,
          config,
          ...
        }:
        {
          environment.systemPackages = with pkgs; [
            (writeShellScriptBin "celluloid-hdr" "ENABLE_HDR_WSI=1 celluloid --mpv-profile=HDR $@")
            celluloid
          ];

          home-manager.users = lib.mapAttrs (user: _: {
            home.file.".config/celluloid" = {
              source = ./config;
              recursive = true;
            };

            dconf.settings = {
              "io/github/celluloid-player/celluloid" = {
                mpv-config-file = "file:///home/${user}/.config/celluloid/celluloid.conf";
              };

              "io/github/celluloid-player/celluloid" = {
                mpv-config-enable = true;
              };

              "io/github/celluloid-player/celluloid" = {
                always-append-to-playlist = true;
              };
            };
          }) config.icedos.users;
        }
      )
    ];

  meta.name = "celluloid";
}
