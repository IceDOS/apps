{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        {
          nixpkgs.overlays = [
            (final: super: {
              sekirofpsunlock = final.callPackage ./package.nix { };
            })
          ];

          security.wrappers.sekirofpsunlock = {
            source = "${pkgs.sekirofpsunlock}/bin/sekirofpsunlock";
            capabilities = "cap_sys_ptrace+ep";
            owner = "root";
            group = "root";
            permissions = "u+rx,g+rx,o+rx";
          };

          icedos.system.tips.list = [
            "sekirofpsunlock lifts Sekiro's 60 FPS cap."
          ];
        }
      )
    ];

  meta.name = "sekirofpsunlock";
}
