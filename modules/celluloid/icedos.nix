{ lib, ... }:

let
  inherit (builtins) fetchurl toFile;
  inherit (lib) importJSON;

  shaderFileName = "FSR.glsl";
  shaderGist = importJSON (fetchurl "https://api.github.com/gists/82219c545228d70c5604f865ce0b0ce5");
  shader = shaderGist.files.${shaderFileName}.content;
in
{
  inputs = {
    celluloid-shader = {
      url = "path://${toFile shaderFileName shader}";
      flake = false;
    };
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      (
        {
          pkgs,
          lib,
          config,
          ...
        }:

        let
          inherit (config.icedos) users;
        in
        {
          environment.systemPackages = with pkgs; [
            (writeShellScriptBin "celluloid-hdr" "ENABLE_HDR_WSI=1 celluloid --mpv-profile=HDR $@")
            celluloid
          ];

          home-manager.users = lib.mapAttrs (user: _: {
            home.file.".config/celluloid/celluloid.conf".source = ./celluloid.conf;
            home.file.".config/celluloid/shaders/FSR.glsl".source = inputs.celluloid-shader;

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
          }) users;
        }
      )
    ];

  meta.name = "celluloid";
}
