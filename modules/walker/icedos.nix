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

          nixosConfig = config;

          accentHex = (icedosLib.generateAccent config).hexNoHash;

          # Plasma ships Klipper, so wl-clip-persist is harmful there (broken
          # image transfers, slow Spectacle); skip it on the running session.
          skipUnderPlasma = pkgs.writeShellScript "wl-clip-persist-skip-under-plasma" ''
            case ":''${XDG_CURRENT_DESKTOP:-}:" in
              *:KDE:*) exit 1 ;;
            esac
          '';
        in
        {
          services.elephant.enable = true;

          # Upstream elephant's minimal PATH breaks Terminal entries and
          # --scope launches; extend it with system paths + user profile.
          systemd.user.services.elephant.environment.PATH = mkForce (
            concatStringsSep ":" [
              "${pkgs.bash}/bin"
              "/run/wrappers/bin"
              "/run/current-system/sw/bin"
              "%h/.nix-profile/bin"
              "/etc/profiles/per-user/%u/bin"
            ]
          );

          # Elephant caches entries at startup; restart it when applications change.
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

          # Track systemPackages so any system change re-runs hm activation
          # (and the restart-elephant hook) on switch.
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

                colors = config.lib.stylix.colors;
                popups = config.stylix.fonts.sizes.popups;

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

                colorReplacements = [
                  colors.base00
                  colors.base02
                  colors.base05
                ];

                fontReplacements = [
                  "font-size: ${scaleFontSize 12}px"
                  "font-size: ${scaleFontSize 24}px"
                  "font-size: ${scaleFontSize 28}px"
                ];

                baseCss = replaceStrings (colorTargets ++ fontTargets) (colorReplacements ++ fontReplacements) (
                  readFile "${pkgs.walker.src}/resources/themes/default/style.css"
                );

                # Match the input background to nautilus' search-bar slot
                # (base03) instead of the upstream lighter window color.
                inputBgHex = colors.base03;

                accentOverride = ''
                  @define-color icedos_accent_color #${accentHex};

                  .input {
                    background: #${inputBgHex};
                  }
                '';

                # Upstream item_clipboard.xml lacks ItemImage; add it so
                # clipboard images render.
                patchedClipboardXml =
                  replaceStrings
                    [
                      ''
                        <property name="spacing">10</property>
                        <child>
                          <object class="GtkBox">
                      ''
                    ]
                    [
                      ''
                        <property name="spacing">10</property>
                        <child>
                          <object class="GtkLabel" id="ItemImageFont">
                            <style>
                              <class name="item-image-text"></class>
                            </style>
                            <property name="width-chars">2</property>
                          </object>
                        </child>
                        <child>
                          <object class="GtkImage" id="ItemImage">
                            <style>
                              <class name="item-image"></class>
                            </style>
                            <property name="icon-size">large</property>
                          </object>
                        </child>
                        <child>
                          <object class="GtkBox">
                      ''
                    ]
                    (readFile "${pkgs.walker.src}/resources/themes/default/item_clipboard.xml");
              in
              {
                services.walker = {
                  enable = true;
                  systemd.enable = true;

                  # Upstream config, minus `theme` (HM injects it) plus force_keyboard_focus.
                  settings =
                    (removeAttrs (importTOML "${pkgs.walker.src}/resources/config.toml") [
                      "theme"
                    ])
                    // {
                      force_keyboard_focus = true;
                    };

                  theme = {
                    style = baseCss + accentOverride;
                    layout.item_clipboard = lib.mkIf (nixosConfig.services.desktopManager.plasma6.enable) patchedClipboardXml;
                  };
                };

                services.wl-clip-persist = {
                  enable = true;
                  clipboardType = "regular";
                };

                systemd.user.services.wl-clip-persist.Service.ExecCondition = "${skipUnderPlasma}";

                # Inotify can't track the ~/.nix-profile symlink chain; also
                # try-restart elephant at the tail of every hm activation.
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
