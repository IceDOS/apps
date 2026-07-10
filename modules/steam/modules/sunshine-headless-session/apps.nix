# Sunshine apps injected into apps.json: one per enabled session (normal/second) ×
# mode (sdr/hdr). `cmd` blocks until the injected Steam exits (auto-detach=false);
# prep-cmd `start` sets the gamescope HDR mode, `stop` tears it down.
{
  pkgs,
  lib,
  cfg,
  sessionApp,
}:

let
  inherit (lib) getExe;

  inherit (cfg)
    sdr
    hdr
    normalSteamSession
    secondarySteamSession
    secondarySteamSessionPath
    ;

  enabledModes = lib.optional sdr "sdr" ++ lib.optional hdr "hdr";
  modeSuffix = mode: lib.optionalString (sdr && hdr) (if mode == "hdr" then " HDR" else " SDR");

  # Box art with a bottom label so Moonlight (no app names on Android) can tell the
  # variants apart; the label appears only when there is another variant to disambiguate.
  steamCover =
    {
      second,
      hdr,
    }:
    let
      label = lib.concatStringsSep " · " (lib.optional second "SECOND" ++ lib.optional hdr "HDR");
      base = "${pkgs.sunshine}/assets/steam.png";
      font = "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf";
    in
    if label == "" then
      base
    else
      pkgs.runCommand "steam-cover-${lib.toLower (lib.replaceStrings [ " · " ] [ "-" ] label)}.png"
        { nativeBuildInputs = [ pkgs.imagemagick ]; }
        ''
          magick ${base} \
            -fill 'rgba(0,0,0,0.72)' -draw 'rectangle 0,655 600,800' \
            \( -background none -fill white -font ${font} -size 540x110 -gravity center label:'${label}' \) \
            -gravity South -geometry +0+22 -composite \
            "$out"
        '';

  mkSteamApp =
    {
      baseName,
      home,
      mode,
    }:
    let
      homeArg = lib.optionalString (home != "") " \"${home}\"";
    in
    {
      name = "${baseName}${modeSuffix mode}";
      image-path = steamCover {
        second = normalSteamSession && secondarySteamSession && home != "";
        hdr = sdr && hdr && mode == "hdr";
      };
      cmd = "${getExe sessionApp} wait${homeArg}";
      auto-detach = false;
      prep-cmd = [
        {
          do = "${getExe sessionApp} start \"${home}\" ${mode}";
          undo = "${getExe sessionApp} stop${homeArg}";
        }
      ];
    };

  steamApps =
    lib.optionals normalSteamSession (
      map (
        mode:
        mkSteamApp {
          baseName = "Steam";
          home = "";
          inherit mode;
        }
      ) enabledModes
    )
    ++ lib.optionals secondarySteamSession (
      map (
        mode:
        mkSteamApp {
          baseName = "Steam (Second Session)";
          home = secondarySteamSessionPath;
          inherit mode;
        }
      ) enabledModes
    );
in
steamApps
