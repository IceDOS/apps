# Steam-only packages for the headless session: the -steamos3 "Switch to Desktop" shim and
# the Moonlight cover art that tells the two Steam sessions apart.
{
  pkgs,
  lib,
  config,
}:

let
  inherit (lib) optionalString;

  # Cover-label font: stylix sans-serif (variable fonts lack static bold).
  fontPkg = config.stylix.fonts.sansSerif.package;
  fontFamily = config.stylix.fonts.sansSerif.name;

  # Box art with a bottom label, so Moonlight can tell the variants apart.
  steamCover =
    {
      second ? false,
    }:
    let
      label = optionalString second "SECOND";
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

  # -steamos3 "Switch to Desktop": stop the Steam that spawned us (matched by HOME).
  steamosSessionSelect = pkgs.writeShellApplication {
    name = "steamos-session-select";
    runtimeInputs = with pkgs; [
      coreutils
      procps
      util-linux
    ];
    text = ''
      # Detach so Steam's call returns instead of blocking on the wait below.
      if [ -z "''${STEAMOS_SESSION_SELECT_DETACHED:-}" ]; then
        STEAMOS_SESSION_SELECT_DETACHED=1 exec setsid -f "$0" "$@"
      fi
      sess_home="''${HOME:-}"
      ${import ./steam-helpers.nix}
      steam_stop
    '';
  };
in
{
  inherit steamosSessionSelect steamCover;
}
