{ lib, icedosLib, ... }:

{
  options.icedos.applications.opencode =
    let
      inherit (lib) readFile;

      inherit (icedosLib)
        mkStrOption
        mkStrListOption
        ;

      inherit ((fromTOML (readFile ./config.toml)).icedos.applications.opencode)
        baseURL
        models
        ;
    in
    {
      baseURL = mkStrOption { default = baseURL; };
      models = mkStrListOption { default = models; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, lib, ... }:
        let
          inherit (lib) listToAttrs;
          inherit (config.icedos.applications.opencode) baseURL models;
        in
        {
          home-manager.sharedModules = [
            {
              programs.opencode = {
                enable = true;

                settings = {
                  "$schema" = "https://opencode.ai/config.json";

                  # @ai-sdk/openai-compatible is fetched from npm on first use
                  # (normal user-runtime network, not a build-time dependency).
                  provider.ollama = {
                    npm = "@ai-sdk/openai-compatible";
                    name = "Ollama (local)";
                    options.baseURL = baseURL;

                    models = listToAttrs (
                      map (m: {
                        name = m;
                        value.name = m;
                      }) models
                    );
                  };
                };
              };
            }
          ];
        }
      )
    ];

  meta = {
    name = "opencode";

    dependencies = [
      { modules = [ "ollama" ]; }
    ];
  };
}
