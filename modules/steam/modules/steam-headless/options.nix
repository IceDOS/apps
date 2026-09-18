{ icedosLib, lib }:

let
  inherit (icedosLib) mkBoolOption mkStrOption;
  inherit (lib) importTOML;

  inherit ((importTOML ./config.toml).icedos.applications.steam.headless-session)
    main
    secondary
    steamOS
    ;
in
{
  # The Steam session(s) the generic headless module streams: each entry becomes one
  # `icedos.applications.sunshine-headless.apps` app (see icedos.nix).

  main = {
    # Inject the normal Steam session (default HOME/account/library).
    enable = mkBoolOption { default = main.enable; };
  };

  secondary = {
    # Inject a second Steam session under secondary.path (separate account/library).
    enable = mkBoolOption { default = secondary.enable; };

    # HOME for the second session; REQUIRED when secondary.enable = true.
    path = mkStrOption { default = secondary.path; };
  };

  # Steam -steamos3: Steam manages gamescope focus natively (no appid tagger) and
  # takes over host Bluetooth.
  steamOS = mkBoolOption { default = steamOS; };
}
