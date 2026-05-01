{ ... }:

{
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
          cfg = config.icedos;

          inherit (lib) readFile replaceStrings;
        in
        {
          services.elephant.enable = true;

          # The upstream services.elephant NixOS module ships a minimal
          # user-systemd PATH (coreutils + grep + sed + systemd, no shell, no
          # /run/current-system/sw/bin). That breaks elephant in two ways:
          #   1. Terminal=true desktop entries fail with `exec: "sh": not
          #      found` because elephant wraps them in `sh -c`.
          #   2. Regular desktop entries appear to "activate" (elephant logs
          #      success) but never spawn the actual app, because elephant
          #      uses `systemd-run --user --scope` and `--scope` mode does the
          #      binary lookup in systemd-run's own process — which inherits
          #      elephant.service's PATH and can't find user-installed apps
          #      like kitty, signal-desktop, etc.
          #
          # Override PATH to include the system binary paths and the user's
          # profile, mirroring what the old hand-rolled walker.service shell
          # wrapper exported. %h and %u are systemd specifiers (home dir,
          # username) so this stays generic across users.
          systemd.user.services.elephant.environment.PATH = lib.mkForce (
            lib.concatStringsSep ":" [
              "${pkgs.bash}/bin"
              "/run/wrappers/bin"
              "/run/current-system/sw/bin"
              "%h/.nix-profile/bin"
              "/etc/profiles/per-user/%u/bin"
            ]
          );

          home-manager.sharedModules = [
            (
              { config, ... }:
              let
                stylixOn = config.stylix.enable or false;
                colors = config.lib.stylix.colors or { };
                popups = config.stylix.fonts.sizes.popups or 10;

                accentSlot = cfg.desktop.stylix.accentBase16Slot or "base0D";
                accentHex = if stylixOn then colors.${accentSlot} else "CBA6F7";

                scaleFontSize = origPx: toString (builtins.floor ((origPx * 1.0 * popups / 12) + 0.5));

                fontTargets = [
                  "font-size: 12px"
                  "font-size: 24px"
                  "font-size: 28px"
                ];

                colorTargets = [
                  "1f1f28"
                  "54546d"
                  "f2ecbc"
                ];

                colorReplacements =
                  if stylixOn then
                    [
                      colors.base00
                      colors.base02
                      colors.base05
                    ]
                  else
                    [
                      "1D1D20"
                      "2E2E32"
                      "EAEAEF"
                    ];

                fontReplacements =
                  if stylixOn then
                    [
                      "font-size: ${scaleFontSize 12}px"
                      "font-size: ${scaleFontSize 24}px"
                      "font-size: ${scaleFontSize 28}px"
                    ]
                  else
                    fontTargets;

                baseCss = replaceStrings (colorTargets ++ fontTargets) (colorReplacements ++ fontReplacements) (
                  readFile "${pkgs.walker.src}/resources/themes/default/style.css"
                );

                # Tint the search input with the stylix accent slot. Appended so it
                # overrides the upstream .input background (lighter(@window_bg_color)).
                accentOverride = ''
                  @define-color icedos_accent_color #${accentHex};

                  .input {
                    background: alpha(@icedos_accent_color, 0.18);
                  }
                '';
              in
              {
                services.walker = {
                  enable = true;
                  systemd.enable = true;

                  # Read upstream config.toml verbatim, override force_keyboard_focus, and
                  # drop the `theme` key so the home-manager module's auto-injected
                  # `settings.theme = theme.name` doesn't collide at the same priority.
                  settings =
                    (removeAttrs (lib.importTOML "${pkgs.walker.src}/resources/config.toml") [
                      "theme"
                    ])
                    // {
                      force_keyboard_focus = true;
                    };

                  theme = {
                    name = "theme";
                    style = baseCss + accentOverride;
                  };
                };

                services.wl-clip-persist = {
                  enable = true;
                  clipboardType = "regular";
                };
              }
            )
          ];

          environment.systemPackages =
            let
              inherit (pkgs) writeShellScriptBin;
            in
            [
              (writeShellScriptBin "walker-applications" ''
                walker -t theme -m desktopapplications
              '')

              (writeShellScriptBin "walker-clipboard" ''
                walker -t theme -m clipboard
              '')

              (writeShellScriptBin "walker-emojis" ''
                walker -t theme -m symbols
              '')
            ];

          environment.sessionVariables.COSMIC_DATA_CONTROL_ENABLED = 1;
        }
      )
    ];

  meta.name = "walker";
}
