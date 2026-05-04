{ icedosLib, lib, ... }:

let
  inherit (icedosLib)
    mkBoolOption
    mkStrListOption
    mkStrOption
    ;
  inherit (lib) mkOption readFile types;

  inherit ((fromTOML (readFile ./config.toml)).icedos.applications.steam.millennium)
    defaultTheme
    disableAnimations
    disableBlur
    enabledPlugins
    pluginIds
    themeIds
    ;

  # Steam Brew theme ID for Adwaita-for-Steam. Used to gate the Stylix
  # Quick CSS overrides (which only fit this theme's `--adw-*-rgb` vars).
  adwaitaThemeId = "7dzdgNotKWgNmQYXc6A0";
in
{
  inputs = {
    millennium = {
      url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";
    };
  };

  options.icedos.applications.steam.millennium = {
    defaultTheme = mkStrOption { default = defaultTheme; };
    disableAnimations = mkBoolOption { default = disableAnimations; };
    disableBlur = mkBoolOption { default = disableBlur; };
    enabledPlugins = mkOption {
      type = types.either types.str (types.listOf types.str);
      default = enabledPlugins;
      description = ''Either the literal string "all" (enable every installed plugin) or a list of plugin IDs to enable.'';
    };
    pluginIds = mkStrListOption { default = pluginIds; };
    themeIds = mkStrListOption { default = themeIds; };
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:

        let
          inherit (builtins) substring toJSON;
          inherit (lib)
            concatMapStringsSep
            fromHexString
            mkIf
            removePrefix
            ;

          cfg = config.icedos.applications.steam.millennium;

          stylixCfg = config.icedos.desktop.stylix or { enable = false; };
          stylixOn = stylixCfg.enable or false;

          # Convert "#RRGGBB" or "RRGGBB" to "R, G, B" decimal triple, the
          # format Adwaita-for-Steam uses for `--adw-*-rgb` custom properties.
          hexToRgbTriple =
            hex:
            let
              h = removePrefix "#" hex;
              r = fromHexString (substring 0 2 h);
              g = fromHexString (substring 2 2 h);
              b = fromHexString (substring 4 2 h);
            in
            "${toString r}, ${toString g}, ${toString b}";

          slot = name: hexToRgbTriple config.lib.stylix.colors.${name};

          accentSlot = stylixCfg.accentBase16Slot;
          fgOnAccentSlot = if (stylixCfg.polarity or "dark") == "light" then "base00" else "base07";

          # Pairs map an Adwaita-for-Steam custom property to a Stylix base16
          # slot. Semantic colors (success/warning/destructive/error) are
          # intentionally omitted — they should stay green/yellow/red across
          # palettes. `--adw-card-bg-rgb` is also skipped: upstream uses an
          # alpha overlay (255,255,255 @ 8%) that already adapts to bg.
          colorPairs = [
            {
              var = "--adw-window-bg-rgb";
              src = "base00";
            }
            {
              var = "--adw-window-fg-rgb";
              src = "base05";
            }
            {
              var = "--adw-view-bg-rgb";
              src = "base00";
            }
            {
              var = "--adw-view-fg-rgb";
              src = "base05";
            }
            {
              var = "--adw-headerbar-bg-rgb";
              src = "base01";
            }
            {
              var = "--adw-headerbar-fg-rgb";
              src = "base05";
            }
            {
              var = "--adw-sidebar-bg-rgb";
              src = "base01";
            }
            {
              var = "--adw-sidebar-fg-rgb";
              src = "base05";
            }
            {
              var = "--adw-secondary-sidebar-bg-rgb";
              src = "base01";
            }
            {
              var = "--adw-secondary-sidebar-fg-rgb";
              src = "base05";
            }
            {
              var = "--adw-popover-bg-rgb";
              src = "base02";
            }
            {
              var = "--adw-popover-fg-rgb";
              src = "base05";
            }
            {
              var = "--adw-dialog-bg-rgb";
              src = "base02";
            }
            {
              var = "--adw-dialog-fg-rgb";
              src = "base05";
            }
            {
              var = "--adw-thumbnail-bg-rgb";
              src = "base01";
            }
            {
              var = "--adw-thumbnail-fg-rgb";
              src = "base05";
            }
            {
              var = "--adw-banner-bg-rgb";
              src = "base02";
            }
            {
              var = "--adw-banner-fg-rgb";
              src = "base05";
            }
            {
              var = "--adw-accent-bg-rgb";
              src = accentSlot;
            }
            {
              var = "--adw-accent-rgb";
              src = accentSlot;
            }
            {
              var = "--adw-accent-fg-rgb";
              src = fgOnAccentSlot;
            }
            {
              var = "--adw-user-online-rgb";
              src = accentSlot;
            }
          ];

          # `!important` on each declaration so we win the cascade over
          # Millennium's runtime themeColors `<style>` injection (which
          # otherwise loads later than our @import and overrides us).
          declarations = concatMapStringsSep "\n  " (
            { var, src }: "${var}: ${slot src} !important;"
          ) colorPairs;

          windows = config.icedos.desktop.windows;

          # Layout preset is fixed to `Windows` (right-side positioning,
          # 3 buttons). Per-button visibility comes from the global
          # `icedos.desktop.windows.{minimizeButton,maximizeButton,closeButton}`
          # flags via CSS rules that hide individual buttons when their flag
          # is false. Selectors match upstream `windowcontrols/windows.css`
          # specificity (body.DesktopUI / html.client_chat_frame +
          # `!important`) so our hide rules win the cascade.
          visibleButtonCount = lib.length (
            lib.optional windows.minimizeButton "minimize"
            ++ lib.optional windows.maximizeButton "maximize"
            ++ [ "close" ]
          );

          # Upstream sets `--adw-windowcontrols-right-buttons: 3` which
          # reserves room for all 3 even when individual buttons are hidden
          # via `visibility: hidden`. Override the count so the reserved
          # right-side margin shrinks to the visible buttons. Close is
          # always present so right-has-buttons stays at 1.
          # Use `:root:root` to outspecify upstream's `:root` :root rule
          # since Quick CSS loads before theme CSS in Millennium's pipeline.
          windowControlVars = ''
            :root:root {
              --adw-windowcontrols-right-buttons: ${toString visibleButtonCount} !important;
              --adw-windowcontrols-right-has-buttons: 1 !important;
            }
          '';

          # Quick CSS loads before theme CSS in Millennium's pipeline, so a
          # rule of equal specificity to upstream's `body.DesktopUI ...
          # .minimizeButton { visibility: visible !important; }` loses the
          # cascade. Repeat the leaf class to bump our specificity above
          # upstream while keeping selectors valid CSS.
          hideButtonRules = lib.concatStrings (
            lib.optional (!windows.minimizeButton) ''
              body.DesktopUI .title-bar-actions .title-area-icon.minimizeButton.minimizeButton,
              html.client_chat_frame .title-bar-actions .title-area-icon.minimizeButton.minimizeButton { visibility: hidden !important; }
            ''
            ++ lib.optional (!windows.maximizeButton) ''
              body.DesktopUI .title-bar-actions .title-area-icon.maximizeButton.maximizeButton,
              body.DesktopUI .title-bar-actions .title-area-icon.restoreButton.restoreButton,
              html.client_chat_frame .title-bar-actions .title-area-icon.maximizeButton.maximizeButton,
              html.client_chat_frame .title-bar-actions .title-area-icon.restoreButton.restoreButton { visibility: hidden !important; }
            ''
          );

          # Upstream `windows.css` hardcodes `right: calc(N * stride)` per
          # button (close=0, max=1, min=2). Hiding middle buttons leaves
          # gaps. Re-pack visible buttons against the right edge by
          # recomputing the `right` offset based on each button's index in
          # the filtered visible-from-right ordering.
          visibleFromRight = [
            "close"
          ]
          ++ lib.optional windows.maximizeButton "maximize"
          ++ lib.optional windows.minimizeButton "minimize";

          mkPositionRule =
            i: btn:
            let
              classes =
                if btn == "maximize" then
                  [
                    "maximizeButton"
                    "restoreButton"
                  ]
                else
                  [ "${btn}Button" ];

              selectors = lib.concatMapStringsSep ",\n" (
                cls:
                "body.DesktopUI .title-bar-actions .title-area-icon.${cls}.${cls},\nhtml.client_chat_frame .title-bar-actions .title-area-icon.${cls}.${cls}"
              ) classes;
            in
            ''
              ${selectors} {
                right: calc(var(--adw-windowcontrols-buttons-margin-outer) + ${toString i} * var(--adw-windowcontrols-button-width) + ${toString i} * var(--adw-windowcontrols-button-gap)) !important;
              }
            '';

          buttonPositionRules = lib.concatStrings (lib.imap0 mkPositionRule visibleFromRight);

          # Performance mitigations for Adwaita-for-Steam on CEF.
          # Each block is opt-in (defaults to enabled in config.toml) so
          # users can re-enable a specific effect by flipping its flag.
          blurCss = lib.optionalString cfg.disableBlur ''
            :root:root, body, body * {
              backdrop-filter: none !important;
              -webkit-backdrop-filter: none !important;
            }
          '';

          animationsCss = lib.optionalString cfg.disableAnimations ''
            :root:root, body, body * {
              transition: none !important;
              animation-duration: 0s !important;
              animation-delay: 0s !important;
            }
          '';

          performanceCss = blurCss + animationsCss;

          customCss = ''
            :root:root {
              ${declarations}
            }

            ${windowControlVars}
            ${hideButtonRules}
            ${buttonPositionRules}
            ${performanceCss}
          '';

          isAdwaitaDefault = cfg.defaultTheme == adwaitaThemeId;

          # Theme/plugin IDs that bootstrap MUST install (defaultTheme +
          # enabledPlugins implicitly install too, on top of anything
          # explicitly listed in themeIds/pluginIds).
          allThemeIds = lib.unique ((lib.optional (cfg.defaultTheme != "") cfg.defaultTheme) ++ cfg.themeIds);

          # `enabledPlugins` is either the literal "all" (every installed
          # plugin gets flagged enabled at patch time) or an explicit list
          # of plugin IDs.
          enableAllPlugins = cfg.enabledPlugins == "all";
          enabledPluginIds = if enableAllPlugins then [ ] else cfg.enabledPlugins;
          allPluginIds = lib.unique (enabledPluginIds ++ cfg.pluginIds);

          # Seeded on first launch. Millennium owns this file at runtime and
          # rewrites it; `force = true` lets HM re-stomp on each rebuild so
          # icedos-declared values win. `hasShownWelcomeModal` must be
          # seeded — HM stomp would otherwise re-show the welcome toast.
          # `themes.activeTheme` and `plugins.enabledPlugins` are NOT seeded
          # here: directory/repo names depend on remote API metadata and are
          # patched in by the bootstrap script via jq after this file lands.
          # Adwaita-only conditions (window controls layout, rounded corners)
          # only seed when defaultTheme matches the Adwaita ID.
          millenniumConfig = {
            general.checkForMillenniumUpdates = false;
            misc.hasShownWelcomeModal = true;
          }
          // lib.optionalAttrs isAdwaitaDefault {
            themes.conditions."Adwaita-for-Steam" = {
              "Window controls layout" = "Windows";
              # Pin explicit "no" so Steam shutdowns of Millennium don't
              # write back a stale "yes" from in-memory state set by an
              # earlier seed.
              "Remove rounded corners" = "no";
            };
          };

          # Bootstrap script: fetches each declared theme/plugin into the
          # user-owned dirs Millennium reads from, only if not already
          # present. Once present Millennium's own auto-updater takes over —
          # users get version bumps without rebuilding NixOS.
          bootstrapScript = pkgs.writeShellScript "millennium-bootstrap" ''
            set -u
            export PATH="${
              lib.makeBinPath [
                pkgs.coreutils
                pkgs.curl
                pkgs.gnugrep
                pkgs.jq
                pkgs.unzip
              ]
            }"

            # Marker filename written into each icedos-installed dir so the
            # prune step can distinguish our installs from user-installed
            # plugins/themes (added via Millennium's UI). Contains the
            # source ID; prune drops dirs whose ID is no longer declared.
            MARKER=".icedos-managed-id"

            # Use Steam Brew's pre-built release zips (contain .millennium/Dist/
            # built artifacts plugins need). Tradeoff: no `.git` so Millennium's
            # in-UI "Update" button warns "Failed to open Git repository" — that
            # warning is cosmetic. For updates, run `icedos rebuild --update`;
            # the rebuild preUpdate hook wipes icedos-managed dirs and this
            # script re-fetches them on the next HM activation.

            fetch_theme() {
              local id="$1"
              local meta name url dest tmp
              meta=$(curl -fsSL "https://steambrew.app/api/v2/details/$id") || {
                echo "[millennium-bootstrap] WARN: theme $id metadata fetch failed" >&2
                return 0
              }
              # Use github.repo for the dir name since Millennium's
              # `themes.activeTheme` config matches dir names.
              name=$(jq -r '.data.github.repo // .name' <<<"$meta")
              url=$(jq -r .download <<<"$meta")
              dest="$HOME/.steam/steam/steamui/skins/$name"
              if [ -d "$dest" ]; then
                if [ -f "$dest/$MARKER" ]; then
                  echo "[millennium-bootstrap] theme $name present, skipping"
                  return 0
                fi
                # Marker missing: dir is partial/aborted state — wipe + refetch.
                echo "[millennium-bootstrap] theme $name marker missing, refetching"
                rm -rf "$dest"
              fi
              tmp=$(mktemp -d)
              trap "rm -rf '$tmp'" RETURN
              if ! curl -fsSL "$url" -o "$tmp/t.zip"; then
                echo "[millennium-bootstrap] WARN: theme $id download failed" >&2
                return 0
              fi
              unzip -q "$tmp/t.zip" -d "$tmp"
              mkdir -p "$(dirname "$dest")"
              mv "$tmp"/*/ "$dest"
              printf '%s\n' "$id" > "$dest/$MARKER"
              echo "[millennium-bootstrap] installed theme $name"
            }

            fetch_plugin() {
              local id="$1"
              local meta name rel dest tmp
              meta=$(curl -fsSL "https://steambrew.app/api/v1/plugin/$id") || {
                echo "[millennium-bootstrap] WARN: plugin $id metadata fetch failed" >&2
                return 0
              }
              name=$(jq -r .repoName <<<"$meta")
              rel=$(jq -r .downloadUrl <<<"$meta")
              dest="$HOME/.local/share/millennium/plugins/$name"
              if [ -d "$dest" ]; then
                if [ -f "$dest/$MARKER" ]; then
                  echo "[millennium-bootstrap] plugin $name present, skipping"
                  return 0
                fi
                # Marker missing: dir is partial/aborted state — wipe + refetch.
                echo "[millennium-bootstrap] plugin $name marker missing, refetching"
                rm -rf "$dest"
              fi
              tmp=$(mktemp -d)
              trap "rm -rf '$tmp'" RETURN
              if ! curl -fsSL "https://steambrew.app$rel" -o "$tmp/p.zip"; then
                echo "[millennium-bootstrap] WARN: plugin $id download failed" >&2
                return 0
              fi
              unzip -q "$tmp/p.zip" -d "$tmp"
              mkdir -p "$(dirname "$dest")"
              mv "$tmp"/*/ "$dest"
              printf '%s\n' "$id" > "$dest/$MARKER"
              echo "[millennium-bootstrap] installed plugin $name"
            }

            # Remove icedos-managed dirs whose marker ID is no longer in the
            # declared ID set. User-installed dirs (no marker) are left
            # alone. Pass declared IDs as space-separated string.
            prune_dir() {
              local root="$1" declared="$2"
              [ -d "$root" ] || return 0
              local d marker_id
              for d in "$root"/*/; do
                marker_id=$(cat "$d/$MARKER" 2>/dev/null || true)
                [ -z "$marker_id" ] && continue
                if ! printf '%s ' $declared | grep -qw "$marker_id"; then
                  echo "[millennium-bootstrap] pruning $(basename "$d") (id $marker_id no longer declared)"
                  rm -rf "$d"
                fi
              done
            }

            ${lib.concatMapStringsSep "\n" (id: ''fetch_theme "${id}"'') allThemeIds}
            ${lib.concatMapStringsSep "\n" (id: ''fetch_plugin "${id}"'') allPluginIds}

            prune_dir "$HOME/.steam/steam/steamui/skins" "${lib.concatStringsSep " " allThemeIds}"
            prune_dir "$HOME/.local/share/millennium/plugins" "${lib.concatStringsSep " " allPluginIds}"

            # Patch Millennium's config.json post-fetch with the resolved
            # theme dir name + plugin repo names. We can't seed these in
            # nix because they require API lookups. jq -e exits non-zero on
            # null result so we guard each block.
            CONFIG="$HOME/.config/millennium/config.json"

            patch_active_theme() {
              local id="$1"
              local meta name
              [ -z "$id" ] && return 0
              meta=$(curl -fsSL "https://steambrew.app/api/v2/details/$id") || return 0
              name=$(jq -r '.data.github.repo // .name' <<<"$meta")
              [ -z "$name" ] && return 0
              tmp=$(mktemp)
              jq --arg n "$name" '.themes.activeTheme = $n' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
              echo "[millennium-bootstrap] active theme set to $name"
            }

            patch_enabled_plugins() {
              # Millennium matches enabledPlugins entries by the plugin's
              # internal `plugin.json` `name` field, NOT the dir name. So
              # for each plugin we want to enable, read its plugin.json.
              local names=()
              local d pj
              ${lib.optionalString enableAllPlugins ''
                # "all" shortcut: enable every installed plugin by reading
                # each one's plugin.json `name`.
                if [ -d "$HOME/.local/share/millennium/plugins" ]; then
                  for d in "$HOME/.local/share/millennium/plugins"/*/; do
                    pj="$d/plugin.json"
                    if [ -f "$pj" ]; then
                      n=$(jq -r .name <"$pj")
                      [ -n "$n" ] && [ "$n" != "null" ] && names+=("$n")
                    fi
                  done
                fi
              ''}
              ${lib.concatMapStringsSep "\n" (id: ''
                # Resolve ID → repo name → read its on-disk plugin.json for
                # the internal name. Fall back to API pluginJson.name if
                # plugin.json missing locally.
                meta=$(curl -fsSL "https://steambrew.app/api/v1/plugin/${id}") || meta=""
                if [ -n "$meta" ]; then
                  repo=$(jq -r .repoName <<<"$meta")
                  pj="$HOME/.local/share/millennium/plugins/$repo/plugin.json"
                  if [ -f "$pj" ]; then
                    n=$(jq -r .name <"$pj")
                  else
                    n=$(jq -r .pluginJson.name <<<"$meta")
                  fi
                  [ -n "$n" ] && [ "$n" != "null" ] && names+=("$n")
                fi
              '') enabledPluginIds}
              if [ ''${#names[@]} -gt 0 ] && [ -f "$CONFIG" ]; then
                tmp=$(mktemp)
                jq --argjson p "$(printf '%s\n' "''${names[@]}" | jq -R . | jq -s 'unique')" \
                  '.plugins.enabledPlugins = $p' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
                echo "[millennium-bootstrap] enabled plugins: ''${names[*]}"
              fi
            }

            if [ -f "$CONFIG" ]; then
              ${lib.optionalString (cfg.defaultTheme != "") ''
                patch_active_theme "${cfg.defaultTheme}"
              ''}
              patch_enabled_plugins
            fi
          '';
        in
        {
          nixpkgs.overlays = [ inputs.millennium.overlays.default ];

          # On `icedos rebuild --update[-hooks]`, drop icedos-managed
          # millennium theme/plugin dirs. `.icedos-managed-id` marker
          # (written by bootstrap) distinguishes ours from user-installed
          # dirs (preserved). For --update (full rebuild), HM activation
          # re-runs bootstrap and re-fetches. For --update-hooks (no HM
          # activation), invoke bootstrap inline.
          icedos.applications.toolset.rebuild.hooks.preUpdate =
            mkIf (allThemeIds != [ ] || allPluginIds != [ ])
              [
                ''
                  for root in "$HOME/.steam/steam/steamui/skins" "$HOME/.local/share/millennium/plugins"; do
                    [ -d "$root" ] || continue
                    for d in "$root"/*/; do
                      if [ -f "$d/.icedos-managed-id" ]; then
                        echo -e "${icedosLib.bash.greenString "millennium"}: wiping $(basename "$d") for refresh"
                        rm -rf "$d"
                      fi
                    done
                  done

                  if [ "''${ICEDOS_HOOKS_ONLY:-0}" = "1" ]; then
                    ${bootstrapScript}
                  fi
                ''
              ];

          home-manager.sharedModules = [
            (
              { lib, ... }:
              {
                xdg.configFile."millennium/config.json" = {
                  force = true;
                  text = toJSON millenniumConfig;
                };

                # Quick CSS color overrides target Adwaita-for-Steam's
                # `--adw-*-rgb` vars; only emit them when Adwaita is the
                # active theme AND Stylix is on (provides the colors).
                xdg.configFile."millennium/quickcss.css" = mkIf (isAdwaitaDefault && stylixOn) {
                  force = true;
                  text = customCss;
                };

                home.activation.millennium-bootstrap = mkIf (allThemeIds != [ ] || allPluginIds != [ ]) (
                  lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                    $DRY_RUN_CMD ${bootstrapScript}
                  ''
                );
              }
            )
          ];
        }
      )
    ];

  meta.name = "steam-millennium";
}
