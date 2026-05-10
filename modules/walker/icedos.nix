{ icedosLib, ... }:

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
          inherit (lib)
            concatStringsSep
            mapAttrs'
            mkForce
            nameValuePair
            readFile
            replaceStrings
            ;

          inherit (config.icedos) users;

          accentHex = (icedosLib.generateAccent config).hexNoHash;
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
          systemd.user.services.elephant.environment.PATH = mkForce (
            concatStringsSep ":" [
              "${pkgs.bash}/bin"
              "/run/wrappers/bin"
              "/run/current-system/sw/bin"
              "%h/.nix-profile/bin"
              "/etc/profiles/per-user/%u/bin"
            ]
          );

          # Elephant caches xdg desktop entries at startup and doesn't
          # rescan, so newly-installed entries (post-rebuild, post-flatpak,
          # etc.) stay invisible until the service is restarted. Watch
          # ~/.local/share/applications and try-restart elephant on any
          # change there.
          systemd.user.paths.elephant-restart = {
            description = "Restart elephant when desktop entries change";
            wantedBy = [ "default.target" ];
            pathConfig.PathChanged = "%h/.local/share/applications";
          };

          systemd.user.services.elephant-restart = {
            description = "Restart elephant when desktop entries change";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${pkgs.systemd}/bin/systemctl --user try-restart elephant.service";
            };
          };

          # extraPackages lands in environment.systemPackages, which doesn't
          # affect home-manager's unit content — so a system-only rebuild
          # leaves hm-<user>.service unchanged and switch-to-configuration
          # never re-runs hm activation, skipping the restart-elephant
          # hook. Tracking systemPackages here flips the unit content
          # whenever a system package is added/removed, forcing hm
          # activation (and the hook) to re-run.
          systemd.services = mapAttrs' (
            user: _:
            nameValuePair "home-manager-${user}" {
              restartTriggers = config.environment.systemPackages;
            }
          ) users;

          home-manager.sharedModules = [
            (
              {
                config,
                lib,
                ...
              }:
              let
                inherit (lib) hm importTOML;

                stylixOn = config.stylix.enable or false;
                colors = config.lib.stylix.colors or { };
                popups = config.stylix.fonts.sizes.popups or 10;

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

                # Override the upstream .input background (lighter(@window_bg_color))
                # with the base16 slot nautilus uses for its search bar so walker's
                # input visually matches the rest of the system surface.
                inputBgHex = if stylixOn then colors.base03 else "353539";

                accentOverride = ''
                  @define-color icedos_accent_color #${accentHex};

                  .input {
                    background: #${inputBgHex};
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
                    (removeAttrs (importTOML "${pkgs.walker.src}/resources/config.toml") [
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

                # The systemd.user.path watcher in the NixOS-side block
                # only catches changes to ~/.local/share/applications
                # (flatpak, Wine, manual installs). Desktop entries from
                # icedos modules and config.toml land in
                # ~/.nix-profile/share/applications, which is a symlink
                # chain inotify can't track across hm switches. So
                # explicitly try-restart elephant at the tail of every
                # home-manager activation — fires once per rebuild,
                # no-op when elephant isn't running.
                home.activation.restart-elephant = hm.dag.entryAfter [ "reloadSystemd" ] ''
                  $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user try-restart elephant.service || true
                '';
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
