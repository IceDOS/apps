#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl git jq nix nix-prefetch-git

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
CORE="${ICEDOS_CORE:-$REPO_ROOT/.icedos-core}"
[ -d "$CORE" ] || CORE="$REPO_ROOT/../core"
[ -f "$CORE/lib/update-lib.sh" ] || {
  echo "ERROR: core not found; set ICEDOS_CORE=/path/to/IceDOS/core" >&2
  exit 1
}
# shellcheck source=/dev/null
. "$CORE/lib/update-lib.sh"

PIN="$SCRIPT_DIR/source.json"
REPO="MaxLastBreath/nx-optimizer"

# package.nix's `build` values, and the filename infix that distinguishes their assets.
BUILDS=(x86_64 aarch64)
infix_for() {
  case "$1" in
    x86_64) echo "" ;;
    aarch64) echo "Arm64." ;;
    *) error "unknown build: $1" ;;
  esac
}

main() {
  banner "nx-optimizer updater"

  # The repo also carries a `yuzu-*` tag namespace from the project's previous life, so
  # releases are filtered to `manager-*` rather than trusting /releases/latest.
  info "Finding latest $REPO manager release..."
  local tag
  tag=$(gh_latest_release "$REPO" '^manager-')
  [ -n "$tag" ] || error "no manager-* release found"
  info "  Latest: $tag"

  local current
  current=$(read_pin "$PIN" .rev)
  if [ "$tag" = "$current" ]; then
    info "  Already up to date ($tag)"
    return
  fi
  info "  Current: ${current:-none}"

  local version="${tag#manager-}"

  local builds_json="{}" build url hash
  for build in "${BUILDS[@]}"; do
    url="https://github.com/$REPO/releases/download/$tag/NX.Optimizer.$(infix_for "$build")$version.AppImage"
    info "  Hashing $build..."
    hash=$(prefetch_file "$url" || echo "")
    require_nonempty "nx-optimizer ($build)" "$url" "$hash"
    builds_json=$(echo "$builds_json" \
      | jq --arg b "$build" --arg url "$url" --arg hash "$hash" \
        '.[$b] = {url: $url, hash: $hash}')
  done

  # The onefile binary embeds its own icon, so the desktop entry's icon is taken from the
  # tagged source tree instead.
  local icon_url icon_hash
  icon_url="https://raw.githubusercontent.com/$REPO/$tag/src/GUI/LOGO.png"
  info "  Hashing icon..."
  icon_hash=$(prefetch_file "$icon_url" || echo "")
  require_nonempty "nx-optimizer (icon)" "$icon_url" "$icon_hash"

  jq -n \
    --arg version "$version" \
    --arg rev "$tag" \
    --argjson builds "$builds_json" \
    --arg icon_url "$icon_url" \
    --arg icon_hash "$icon_hash" \
    '{version: $version, rev: $rev, builds: $builds, icon: {url: $icon_url, hash: $icon_hash}}' \
    | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
