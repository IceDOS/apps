# The Sunshine app list: one entry per configured app, all launched through the
# session helper so a stream starts/waits/stops exactly the app it asked for.
{
  lib,
  apps,
  sessionApp,
}:

let
  inherit (lib) getExe;

  # Sunshine tokenizes these strings itself, and nothing is expanded (no shell). A name with a
  # space is passed as one argument only in the double-quoted form: with single quotes the
  # 2026-09-18 01:58 run died as `unknown app`. An assertion rejects a name with a double quote.
  nameArg = name: "\"${builtins.replaceStrings [ "\"" "\\" ] [ "\\\"" "\\\\" ] name}\"";
in
map (
  app:
  {
    name = app.name;
    cmd = "${getExe sessionApp} wait ${nameArg app.name}";
    auto-detach = app.auto-detach;
    prep-cmd = [
      {
        do = "${getExe sessionApp} start ${nameArg app.name}";
        undo = "${getExe sessionApp} stop ${nameArg app.name}";
      }
    ];
    # An empty image-path is left out: Sunshine serves its own default image for the app.
  }
  // lib.optionalAttrs (app.image-path != "") { inherit (app) image-path; }
) apps
