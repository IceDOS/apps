# Sunshine apps for the headless session, one per enabled session. `cmd` blocks
# until Steam exits; prep-cmd `start` launches gamescope, `stop` tears it down.
{
  pkgs,
  lib,
  cfg,
  config,
  sessionApp,
}:

let
  inherit (lib) getExe;

  inherit (cfg)
    normalSteamSession
    secondarySteamSession
    secondarySteamSessionPath
    ;

  # Cover-label font: the desktop's stylix sans-serif, else DejaVu (resolved in the
  # builder: variable fonts have no static bold face, and fontconfig mis-picks italic).
  stylixOn = config.stylix.enable or false;
  fontPkg = if stylixOn then config.stylix.fonts.sansSerif.package else pkgs.dejavu_fonts;
  fontFamily = if stylixOn then config.stylix.fonts.sansSerif.name else "DejaVu Sans";

  # Box art with a bottom label so Moonlight can tell the variants apart (only when >1).
  steamCover =
    { second }:
    let
      label = lib.optionalString second "SECOND";
      base = "${pkgs.sunshine}/assets/steam.png";
    in
    if label == "" then
      base
    else
      pkgs.runCommand "steam-cover-${lib.toLower label}.png"
        {
          nativeBuildInputs = [
            pkgs.imagemagick
            pkgs.fontconfig
          ];
          FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ fontPkg ]; };
        }
        ''
          fontfile="$(fc-match -f '%{file}' "${fontFamily}:style=Bold")"
          magick ${base} \
            -fill 'rgba(0,0,0,0.72)' -draw 'rectangle 0,655 600,800' \
            \( -background none -fill white -font "$fontfile" -size 540x110 -gravity center label:'${label}' \) \
            -gravity South -geometry +0+22 -composite \
            "$out"
        '';

  mkSteamApp =
    {
      baseName,
      home,
    }:
    let
      homeArg = lib.optionalString (home != "") " \"${home}\"";
    in
    {
      name = baseName;
      image-path = steamCover {
        second = normalSteamSession && secondarySteamSession && home != "";
      };
      cmd = "${getExe sessionApp} wait${homeArg}";
      auto-detach = false;
      prep-cmd = [
        {
          do = "${getExe sessionApp} start \"${home}\"";
          undo = "${getExe sessionApp} stop${homeArg}";
        }
      ];
    };

  steamApps =
    lib.optionals normalSteamSession ([
      (mkSteamApp {
        baseName = "Steam";
        home = "";
      })
    ])
    ++ lib.optionals secondarySteamSession ([
      (mkSteamApp {
        baseName = "Steam (Second Session)";
        home = secondarySteamSessionPath;
      })
    ]);
in
steamApps
