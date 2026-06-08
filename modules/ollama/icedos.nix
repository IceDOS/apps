{ lib, icedosLib, ... }:

{
  options.icedos.applications.ollama =
    let
      inherit (lib) readFile;

      inherit (icedosLib)
        mkBoolOption
        mkStrOption
        mkNumberOption
        mkStrListOption
        ;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.ollama)
        vulkan
        host
        port
        loadModels
        ;
    in
    {
      vulkan = mkBoolOption { default = vulkan; };
      host = mkStrOption { default = host; };
      port = mkNumberOption { default = port; };
      loadModels = mkStrListOption { default = loadModels; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, pkgs, ... }:
        let
          inherit (config.icedos.applications.ollama)
            vulkan
            host
            port
            loadModels
            ;
        in
        {
          services.ollama = {
            enable = true;
            package = if vulkan then pkgs.ollama-vulkan else pkgs.ollama;
            inherit host port loadModels;
          };
        }
      )
    ];

  meta.name = "ollama";
}
