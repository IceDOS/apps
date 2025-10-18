{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        let
          inherit (pkgs) flatpak writeShellScriptBin;
        in
        {
          icedos.applications.toolset.commands = [
            (
              let
                command = "flatpak-init";
                flatpakBin = "${flatpak}/bin/flatpak";
              in
              {
                inherit command;

                bin = "${writeShellScriptBin command ''
                  ${flatpakBin} remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
                  ${flatpakBin} install flathub com.github.tchx84.Flatseal
                  ${flatpakBin} install flathub io.github.kolunmi.Bazaar
                ''}/bin/${command}";

                help = "add flathub as a flatpak repo and install flatpak helper tools";
              }
            )
          ];

          services.flatpak.enable = true;
        }
      )
    ];

  meta.name = "flatpak";
}
