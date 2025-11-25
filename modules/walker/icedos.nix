{ ... }:

{
  outputs.nixosModules =
    { ... }:

    [
      (
        {
          config,
          icedosLib,
          lib,
          pkgs,
          ...
        }:

        let
          inherit (lib)
            mapAttrs
            readFile
            replaceStrings
            ;

          cfg = config.icedos;

          accentColor = icedosLib.generateAccentColor {
            accentColor = cfg.desktop.accentColor;
            gnomeAccentColor = cfg.desktop.gnome.accentColor;
            hasGnome = lib.hasAttr "gnome" cfg.desktop;
          };

          package = pkgs.walker;
        in
        {
          environment.sessionVariables.COSMIC_DATA_CONTROL_ENABLED = 1;

          environment.systemPackages = with pkgs; [
            package
            wl-clipboard

            (pkgs.writeShellScriptBin "walker-applications" ''
              walker -s theme -m applications
            '')

            (pkgs.writeShellScriptBin "walker-clipboard" ''
              walker -s theme -m clipboard
            '')

            (pkgs.writeShellScriptBin "walker-emojis" ''
              walker -s theme -m emojis
            '')
          ];

          home-manager.users = mapAttrs (user: _: {
            wayland.windowManager.hyprland.settings.bind = [
              "$mainMod, E, exec, walker-emojis"
              "$mainMod, R, exec, walker-applications"
              "$mainMod, V, exec, walker-clipboard"
            ];

            home.file =
              let
                force = true;
              in
              {
                ".config/walker/config.toml" = {
                  inherit force;

                  text =
                    replaceStrings
                      [ ''app_launch_prefix = ""'' ]
                      [ ''app_launch_prefix = "${pkgs.uwsm}/bin/uwsm app -- "'' ]
                      (readFile "${package.src}/internal/config/config.default.toml");
                };

                ".config/walker/themes/theme.css" = {
                  inherit force;

                  text = ''
                    #window,
                    #box,
                    #search,
                    #password,
                    #input,
                    #typeahead,
                    #spinner,
                    #list,
                    child,
                    scrollbar,
                    slider,
                    #item,
                    #text,
                    #bar,
                    #listplaceholder,
                    #label,
                    #sub,
                    #activationlabel {
                      all: unset;
                    }

                    #window {
                      color: #ffffff;
                    }

                    #box {
                      background: #1D1D20;
                      border-color: #464646;
                      border-radius: 10px;
                      border-style: solid;
                      border-width: 1px;
                      padding: 20px;
                    }

                    #search {
                      padding-top: 0px;
                      padding-bottom: 0px;
                      padding-left: 5px;
                      padding-right: 5px;
                      background: #2E2E32;
                      border-radius: 5px;
                      margin-bottom: 20px;
                      border: 2px solid ${accentColor};
                    }

                    #password,
                    #input,
                    #typeahead {
                      padding: 5px;
                      border-radius: 10px;
                    }

                    #input > *:first-child,
                    #typeahead > *:first-child {
                      margin-right: 10px;
                    }

                    #typeahead {
                      color: #c4c4c4;
                    }

                    #input placeholder {
                      opacity: 0.5;
                    }

                    #list {
                      background: #2E2E32;
                      border-radius: 10px;
                    }

                    child:selected,
                    child:hover {
                      background: #3d3d40;
                    }

                    #item {
                      padding: 10px;
                      border-bottom: 1px solid #464646;
                    }

                    #sub {
                      font-size: smaller;
                      color: #8e8e8e;
                    }

                    #activationlabel {
                      opacity: 0.5;
                    }

                    .activation #activationlabel {
                      opacity: 1;
                      color: ${accentColor};
                    }

                    .activation #text,
                    .activation #icon,
                    .activation #search {
                      opacity: 0.5;
                    }
                  '';
                };

                ".config/walker/themes/theme.json" = {
                  inherit force;

                  text = ''
                    {
                      "ui": {
                        "anchors": {
                          "top": true,
                          "bottom": true
                        },
                        "window": {
                          "v_align": "center",
                          "box": {
                            "width": 400,
                            "margins": {
                              "top": 200
                            },
                            "v_align": "center",
                            "h_align": "center",
                            "search": {
                              "width": 400,
                              "spacing": 5
                            },
                            "scroll": {
                              "list": {
                                "width": 400,
                                "marker_color": "${accentColor}",
                                "max_height": 300,
                                "min_width": 400,
                                "max_width": 400,
                                "item": {
                                  "spacing": 10,
                                  "activation_label": {
                                    "x_align": 1.0,
                                    "width": 20
                                  },
                                  "icon": {
                                    "theme": "Theme"
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  '';
                };
              };

            systemd.user.services.walker = {
              Unit.Description = "Walker - Application Runner";
              Install.WantedBy = [ "graphical-session.target" ];

              Service = {
                ExecStart = "${pkgs.writeShellScriptBin "walker-service" ''
                  base_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                  nix_system_path="/run/current-system/sw/bin"
                  nix_user_path="''${HOME}/.nix-profile/bin"
                  export PATH="''${base_path}:''${nix_system_path}:''${nix_user_path}:$PATH"
                  export TERM="kitty"

                  ${package}/bin/walker --gapplication-service
                ''}/bin/walker-service";

                Nice = "-20";
                Restart = "on-failure";
                StartLimitIntervalSec = 60;
                StartLimitBurst = 60;
              };
            };
          }) cfg.users;
        }
      )
    ];

  meta.name = "walker";
}
