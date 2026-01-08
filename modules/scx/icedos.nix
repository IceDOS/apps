{ icedosLib, ... }:

{
  options.icedos.applications.scx = {
    extraArgs = icedosLib.mkStrListOption { default = [ ]; };
    scheduler = icedosLib.mkStrOption { default = "lavd"; };
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
          inherit (lib)
            getBin
            mkForce
            mkIf
            ;

          inherit (pkgs) callPackage runtimeShell writeShellScriptBin;
          inherit (pkgs.scx) full;

          scx = config.icedos.applications.scx;
          isCake = scx.scheduler == "cake";

          package =
            if !isCake then
              full
            else
              full.overrideAttrs (old: {
                postInstall = old.postInstall + ''
                  cp ${getBin (callPackage ./scx-cake/package.nix { })}/bin/* ${placeholder "out"}/bin/
                '';
              });
        in
        {
          services.scx = {
            inherit package;
            enable = true;
            extraArgs = scx.extraArgs;
            scheduler = mkIf (!isCake) "scx_${scx.scheduler}";
          };

          systemd.services.scx = mkIf isCake {
            environment.SCX_SCHEDULER = mkForce "scx_cake";

            serviceConfig.ExecStart = mkForce "${writeShellScriptBin "scx-watcher" ''
              while :; do
                ${runtimeShell} -c 'exec ${package}/bin/''${SCX_SCHEDULER_OVERRIDE:-$SCX_SCHEDULER} ''${SCX_FLAGS_OVERRIDE:-$SCX_FLAGS}'
              done
            ''}/bin/scx-watcher";
          };

        }
      )
    ];

  meta.name = "scx";
}
