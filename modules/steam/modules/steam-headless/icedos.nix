# Steam's place in the generic headless-Sunshine module: this module names the Steam
# session(s) it streams and keeps Steam itself working (rfkill, InputPlumber,
# steamwebhelper's audio name). Gamescope, Sunshine and the session helper all live in
# `sunshine-headless`.
{ icedosLib, lib, ... }:

{
  options.icedos.applications.steam.headless-session = import ./options.nix {
    inherit icedosLib lib;
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
          cfg = config.icedos.applications.steam.headless-session;
          headless = config.icedos.applications.sunshine-headless;

          inherit (lib) mkIf optional optionals;

          steamOS = cfg.steamOS;

          steamPkg = ((import ../../lib/resolved-steam.nix) { inherit config pkgs; }).resolved;

          inherit (import ./packages.nix { inherit pkgs lib config; }) steamosSessionSelect steamCover;

          # Steam's hooks (Big Picture launch, appid tagging, drain) for the generic helper.
          steamHooks = import ./hooks.nix {
            inherit lib steamOS;

            steamHelpers = import ./steam-helpers.nix;

            inherit (headless.gamescope) colorManagement mangoApp nativeWayland;
          };

          # One Sunshine app per enabled session: `name` is the Moonlight entry, `home`
          # the account. Fixed slugs keep the scope and the runtime paths stable.
          mkSession =
            {
              name,
              home,
              second,
            }:
            {
              inherit name home;

              slug = if home == "" then "steam" else "steam_second";

              # The start hook sets the argv (`steam -gamepadui [-steamos3]`).
              command = [ ];

              image-path = steamCover { inherit second; };
              auto-detach = false;

              # The shim's PATH is where the bare `steam` target is resolved.
              packages = [ steamPkg ] ++ optional steamOS steamosSessionSelect;

              # Steam expects gamescope's --steam session (appid focus, baselayer, HUD);
              # every other app runs on a plain compositor.
              steamMode = true;

              # The shim is what hides the host pads and publishes the virtual ones.
              # Same gate as before the split: gamescope takes the shim for inputInjection.
              shim = steamOS || headless.session.controllers.isolateVirtual;

              helpers = steamHooks.helpers;
              hooks = steamHooks.hooks;
            };

          # The second session gets a labelled cover only while both are enabled.
          apps =
            optionals cfg.main.enable [
              (mkSession {
                name = "Steam";
                home = "";
                second = false;
              })
            ]
            ++ optionals cfg.secondary.enable [
              (mkSession {
                name = "Steam (Second Session)";
                home = cfg.secondary.path;
                second = cfg.main.enable;
              })
            ];
        in
        {
          icedos.applications.sunshine-headless.apps = apps;

          # -steamos3 Steam opens /dev/rfkill O_RDWR; `input` is the shim's group and has
          # no human members (the generic module asserts it).
          services.udev.packages = optional steamOS (
            pkgs.writeTextDir "etc/udev/rules.d/70-steam-rfkill-access.rules" ''
              SUBSYSTEM=="misc", KERNEL=="rfkill", GROUP="input", MODE="0660"
            ''
          );

          # -steamos3 Steam needs InputPlumber for controller ordering/routing.
          services.inputplumber.enable = mkIf steamOS true;

          # Rename steamwebhelper's PulseAudio app: WirePlumber's shared "Chromium" key
          # would poison desktop Chromium apps.
          services.pipewire.extraConfig.pipewire-pulse."90-steam-headless-audio-name" = {
            "pulse.rules" = [
              {
                matches = [ { "application.process.binary" = "steamwebhelper"; } ];
                actions.update-props."application.name" = "Steam";
              }
            ];
          };

          assertions = [
            {
              assertion = !cfg.secondary.enable || cfg.secondary.path != "";
              message = "icedos.applications.steam.headless-session.secondary.path must be set (non-empty) when secondary.enable is true; it is the second session's HOME.";
            }
          ];
        }
      )
    ];

  meta = {
    name = "steam-headless";

    dependencies = [
      {
        modules = [
          "steam"
          "sunshine-headless"
        ];
      }
    ];
  };
}
