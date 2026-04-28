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

          inherit (lib)
            hasAttr
            optional
            readFile
            replaceStrings
            ;

          generateTargetArray =
            base:
            base
            ++ optional (hasAttr "desktop" cfg && hasAttr "cosmic" cfg.desktop) "cosmic-session.target"
            ++ optional (hasAttr "desktop" cfg && hasAttr "gnome" cfg.desktop) "gnome-session.target"
            ++ optional (hasAttr "desktop" cfg && hasAttr "hyprland" cfg.desktop) "hyprland-session.target";
        in
        {
          home-manager.sharedModules = [
            {
              home.file = {
                ".config/walker/config.toml".text =
                  replaceStrings [ "force_keyboard_focus = false" ] [ "force_keyboard_focus = true" ]
                    (readFile "${pkgs.walker.src}/resources/config.toml");

                ".config/walker/themes/theme/style.css".text =
                  let
                    stylixOn = config.stylix.enable or false;
                    colors = config.lib.stylix.colors or { };
                    popups = config.stylix.fonts.sizes.popups or 10;

                    accentSlot = config.icedos.desktop.stylix.accentBase16Slot or "base0D";
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
                  baseCss + accentOverride;
              };

              systemd.user.services.walker = {
                Unit = {
                  Description = "Walker - Application Runner";
                  After = generateTargetArray [ "graphical-session.target" ];
                  PartOf = "graphical-session.target";
                  StartLimitIntervalSec = 60;
                  StartLimitBurst = 60;

                  # Restart walker (and elephant subprocess) when system packages change,
                  # so new desktop entries are picked up. The store path changes when
                  # environment.systemPackages changes, triggering sd-switch to restart.
                  X-Restart-Triggers = [ "${config.system.path}" ];
                };

                Install.WantedBy = generateTargetArray [ ];

                Service = {
                  ExecStart = "${pkgs.writeShellScriptBin "walker-service" ''
                    base_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                    nix_system_path="/run/current-system/sw/bin"
                    nix_user_path="''${HOME}/.nix-profile/bin"
                    export PATH="''${base_path}:''${nix_system_path}:''${nix_user_path}:$PATH"

                    elephant &
                    wl-clip-persist --clipboard regular &

                    while :; do
                      walker --gapplication-service || echo 'walker crashed unexpectedly!'
                    done
                  ''}/bin/walker-service";

                  Nice = "-20";
                  Restart = "on-failure";
                };
              };
            }
          ];

          environment.systemPackages =
            let
              inherit (pkgs)
                elephant
                walker
                wl-clip-persist
                writeShellScriptBin
                ;
            in
            [
              elephant
              walker
              wl-clip-persist

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
