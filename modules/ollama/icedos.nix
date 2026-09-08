{ lib, icedosLib, ... }:

{
  options.icedos.applications.ollama =
    let
      inherit (lib) importTOML;

      inherit (icedosLib)
        mkBoolOption
        mkStrOption
        mkNumberOption
        mkStrListOption
        ;

      inherit ((importTOML ./config.toml).icedos.applications.ollama)
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
            any
            attrNames
            listToAttrs
            mkIf
            ;

          inherit (config.icedos) applications users;

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
          home-manager.sharedModules =
            mkIf (any (user: config.home-manager.users.${user}.programs.opencode.enable) (attrNames users))
              [
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

          icedos.system.tips.list = [
            "ollama run <model> chats with an AI model that runs on your own machine."
          ]
          ++ lib.optionals (loadModels != [ ]) [
            "The AI models you listed in config.toml download themselves on rebuild."
          ];
        }
      )
    ];

  meta.name = "ollama";
}
