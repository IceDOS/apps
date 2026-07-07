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
        {
          config,
          pkgs,
          lib,
          ...
        }:

        let
          inherit (lib)
            hasAttr
            listToAttrs
            mkIf
            ;

          inherit (config.icedos) applications;

          inherit (applications.ollama)
            vulkan
            host
            port
            loadModels
            ;

          baseURL = "http://${host}:${toString port}/v1";
        in
        {
          services.ollama = {
            enable = true;
            package = if vulkan then pkgs.ollama-vulkan else pkgs.ollama;
            inherit host port loadModels;
          };

          # Expose the local ollama endpoint to opencode when it is enabled.
          home-manager.sharedModules = mkIf (hasAttr "opencode" applications) [
            {
              # @ai-sdk/openai-compatible is fetched from npm on first use
              # (normal user-runtime network, not a build-time dependency).
              programs.opencode.settings.provider.ollama = {
                npm = "@ai-sdk/openai-compatible";
                name = "Ollama (local)";
                options.baseURL = baseURL;

                models = listToAttrs (
                  map (m: {
                    name = m;
                    value.name = m;
                  }) loadModels
                );
              };
            }
          ];
        }
      )
    ];

  meta.name = "ollama";
}
