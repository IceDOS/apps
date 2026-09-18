{ icedosLib, lib, ... }:

{
  options.icedos.applications.sunshine =
    let
      inherit (icedosLib) mkAttrsOption mkBoolOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.applications.sunshine)
        applications
        autoStart
        capSysAdmin
        openFirewall
        settings
        shortcutStartsUnit
        ;
    in
    {
      applications = mkAttrsOption { default = applications; };
      autoStart = mkBoolOption { default = autoStart; };
      capSysAdmin = mkBoolOption { default = capSysAdmin; };
      openFirewall = mkBoolOption { default = openFirewall; };
      settings = mkAttrsOption { default = settings; };

      # shortcutStartsUnit: start the systemd unit (generated conf, correct
      # name/ports) instead of a second bare instance on 47989.
      shortcutStartsUnit = mkBoolOption { default = shortcutStartsUnit; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          ...
        }:

        let
          inherit (config.icedos.applications.sunshine)
            applications
            autoStart
            capSysAdmin
            openFirewall
            settings
            shortcutStartsUnit
            ;

          # headlessShortcut: optional; the headless module may not be loaded,
          # then there is no entry and this stays false.
          headlessShortcut =
            config.icedos.applications.sunshine-headless.session.sunshine.desktopShortcut or false;
        in
        {
          services.sunshine = {
            enable = true;

            inherit
              applications
              autoStart
              capSysAdmin
              openFirewall
              settings
              ;
          };

          # nixpkgs.overlays/sunshine: swap in a symlinkJoin whose desktop
          # entries start the units; gated on shortcutStartsUnit (primary
          # entry) or the headless module's desktopShortcut.
          nixpkgs.overlays = lib.mkIf (shortcutStartsUnit || headlessShortcut) [
            (
              final: previous:
              let
                primaryUnit = "sunshine";
                headlessUnit = "sunshine-headless";

                # Drop the terminal action (bare second instance on 47989,
                # bypassing the unit) and point the Exec at the unit.
                desktopToUnit = file: unit: ''
                  substituteInPlace ${file} \
                    --replace-fail $'Actions=RunInTerminal;\n' "" \
                    --replace-fail $'\n[Desktop Action RunInTerminal]\nExec=gio launch ${previous.sunshine}/share/applications/dev.lizardbyte.app.Sunshine.terminal.desktop\nIcon=application-x-executable\nName=Run in Terminal\n' "" \
                    --replace-fail 'Exec=sunshine' 'Exec=/run/current-system/sw/bin/systemctl --user start ${unit}'
                '';
              in
              {
                sunshine = final.symlinkJoin {
                  name = "sunshine-desktop-patched";
                  paths = [ previous.sunshine ];
                  # Keep .version (headless gid build) and meta.mainProgram
                  # (getExe) readable; both come from the original binary.
                  passthru = previous.sunshine.passthru // {
                    version = previous.sunshine.version;
                    meta = previous.sunshine.meta;
                  };
                  postBuild =
                    lib.optionalString shortcutStartsUnit ''
                      # Replace the shipped shortcut with one that starts the systemd unit.
                      rm $out/share/applications/dev.lizardbyte.app.Sunshine.desktop
                      cp ${previous.sunshine}/share/applications/dev.lizardbyte.app.Sunshine.desktop $out/share/applications/dev.lizardbyte.app.Sunshine.desktop
                      ${desktopToUnit "$out/share/applications/dev.lizardbyte.app.Sunshine.desktop" primaryUnit}
                      # The NoDisplay terminal entry ships bare too; point it at the unit.
                      rm $out/share/applications/dev.lizardbyte.app.Sunshine.terminal.desktop
                      cp ${previous.sunshine}/share/applications/dev.lizardbyte.app.Sunshine.terminal.desktop $out/share/applications/dev.lizardbyte.app.Sunshine.terminal.desktop
                      substituteInPlace $out/share/applications/dev.lizardbyte.app.Sunshine.terminal.desktop                         --replace-fail 'Exec=sunshine' 'Exec=/run/current-system/sw/bin/systemctl --user start ${primaryUnit}'
                    ''
                    + lib.optionalString headlessShortcut (
                      if shortcutStartsUnit then
                        # Second entry for the headless daemon, derived from the patched
                        # shortcut so it tracks upstream desktop-file updates.
                        ''
                          cp $out/share/applications/dev.lizardbyte.app.Sunshine.desktop $out/share/applications/sunshine-headless.desktop
                          substituteInPlace $out/share/applications/sunshine-headless.desktop \
                            --replace-fail 'Name=Sunshine' 'Name=Sunshine - Headless' \
                            --replace-fail '--user start ${primaryUnit}' '--user start ${headlessUnit}'
                        ''
                      else
                        # Headless-only mode: primary stays unpatched, headless
                        # entry patches the shipped file.
                        ''
                          cp ${previous.sunshine}/share/applications/dev.lizardbyte.app.Sunshine.desktop $out/share/applications/sunshine-headless.desktop
                          ${desktopToUnit "$out/share/applications/sunshine-headless.desktop" headlessUnit}
                          substituteInPlace $out/share/applications/sunshine-headless.desktop \
                            --replace-fail 'Name=Sunshine' 'Name=Sunshine - Headless'
                        ''
                    );
                };
              }
            )
          ];

          icedos.system.tips.list =
            lib.optionals openFirewall [
              "Sunshine is reachable from the other devices on your network."
            ]
            ++ lib.optionals autoStart [
              "Sunshine starts with your session, so streaming is ready whenever you are."
            ];
        }
      )
    ];

  meta.name = "sunshine";
}
