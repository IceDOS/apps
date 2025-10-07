{ ... }:

let
  name = "rvc-rocm";
in
{
  outputs.nixosModules =
    { ... }:
    [
      (
        {
          pkgs,
          ...
        }:
        {
          nixpkgs.overlays = [
            (final: super: {
              ${name} = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [
            (
              let
                inherit (pkgs) rvc-rocm writeShellScriptBin;
                rvcBin = "${rvc-rocm}/bin/${name}";

                rvcWrapped = ''${writeShellScriptBin name ''
                  steam-run ${rvcBin} &
                  steam_run_pid="$!"

                  sleep 1
                  kill -9 "$steam_run_pid"

                  ${rvcBin}
                ''}/bin/${name}'';
              in
              writeShellScriptBin "${name}" ''
                nix-shell -p steam-run-free --run ${rvcWrapped}
              ''
            )
          ];
        }
      )
    ];

  meta.name = name;
}
