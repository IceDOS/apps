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
        { pkgs, ... }:

        {
          environment.systemPackages = with pkgs; [
            celluloid
          ];

          home-manager.sharedModules = [
            (
              { config, ... }:

              {
                home.file.".config/celluloid/celluloid.conf".source = ./celluloid.conf;
                home.file.".config/celluloid/shaders/FSR.glsl".source = inputs.celluloid-shader;

                dconf.settings = {
                  "io/github/celluloid-player/celluloid" = {
                    always-append-to-playlist = true;
                    mpv-config-enable = true;
                    mpv-config-file = "file://${config.home.homeDirectory}/.config/celluloid/celluloid.conf";
                  };
                };
              }
            )
          ];
        }
      )
    ];

  meta.name = "celluloid";
}
