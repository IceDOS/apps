{
  icedosLib,
  ...
}:

let
  name = "rvc-rocm";
  version = "b2332";
in
{
  options.icedos.applications.rvc-rocm.useWindowsIcon =
    let
      inherit (icedosLib) mkBoolOption;
    in
    mkBoolOption { default = false; };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          pkgs,
          ...
        }:
        {
          nixpkgs.overlays = [
            (final: super: {
              ${name} = final.callPackage ./package.nix { inherit version; };
            })
          ];

          environment.systemPackages = [
            (
              let
                inherit (pkgs)
                  imagemagick
                  makeDesktopItem
                  runCommand
                  rvc-rocm
                  stdenv
                  writeShellScriptBin
                  ;

                inherit (stdenv) mkDerivation;
                rvcName = "${name}-wrapped";
                rvcBin = "${rvc-rocm}/bin/${rvcName}";

                rvcWrapped = ''${writeShellScriptBin name ''
                  steam-run ${rvcBin} &
                  steam_run_pid="$!"

                  sleep 1
                  kill -9 "$steam_run_pid"

                  ${rvcBin}
                ''}/bin/${name}'';

                nixShellInit = writeShellScriptBin "${name}" ''
                  nix-shell -p steam-run-free --run ${rvcWrapped}
                '';

                icon = "${
                  runCommand "rvc-icon" { } ''
                    mkdir -p $out

                    ${imagemagick}/bin/magick convert ${
                      if config.icedos.applications.rvc-rocm.useWindowsIcon then
                        "${
                          let
                            inherit (pkgs) fetchFromGitHub;
                          in
                          fetchFromGitHub {
                            hash = "sha256-2iXOgg75MS4G3Jdwyg49DNDbD//4RnhL9LrJBe+W9zU=";
                            owner = "deiteris";
                            repo = "voice-changer";
                            tag = version;
                          }
                        }/server/vc_64.ico"
                      else
                        ''${rvc-rocm}/lib/${rvcName}/_internal/dist/favicon.ico''
                    } $out/icon.png
                  ''
                }/icon.png";

                desktopItem = makeDesktopItem {
                  inherit icon;
                  categories = [ "Utility" ];
                  desktopName = "RVC";
                  exec = "${nixShellInit}/bin/${name}";
                  name = "rvc-rocm";
                  terminal = true;
                };
              in
              mkDerivation {
                inherit version;
                pname = "${name}";
                src = nixShellInit;

                installPhase = ''
                  mkdir -p $out/bin $out/share/applications

                  ln -s $src/bin/${name} $out/bin/${name}
                  ln -s ${desktopItem}/share/applications/*.desktop $out/share/applications/
                '';
              }
            )
          ];
        }
      )
    ];

  meta.name = name;
}
