#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl git jq nix

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
REPO="droogie/bbhost"

main() {
  banner "bbhost updater"

  info "Finding latest $REPO release..."
  local tag
  tag=$(gh_latest_release "$REPO")
  [ -n "$tag" ] || error "no release found"
  info "  Latest: $tag"

  local current
  current=$(read_pin "$PIN" .rev)
  if [ "$tag" = "$current" ]; then
    info "  Already up to date ($tag)"
    return
  fi
  info "  Current: ${current:-none}"

  # Tags are `vX.Y.Z`; the derivation's version carries no prefix.
  local version="${tag#v}"

  # The release ships a debug build beside the tarball, so resolve the Linux
  # tarball by name rather than constructing a URL that could quietly 404.
  local url
  url=$(gh_release_asset_url "$REPO" "$tag" '^bbhost-linux-v[0-9].*\.tar\.gz$')
  [ -n "$url" ] || error "no Linux tarball in $tag"
  info "  Asset: $url"

  info "  Computing hash..."
  local hash
  hash=$(prefetch_file "$url" || echo "")
  require_nonempty bbhost "$version" "$tag" "$url" "$hash"
  info "  Hash: $hash"

  local icon_url="https://raw.githubusercontent.com/$REPO/$tag/res/bbhost.ico"
  info "  Hashing icon..."
  local icon_hash
  icon_hash=$(prefetch_file "$icon_url" || echo "")
  require_nonempty "bbhost (icon)" "$icon_url" "$icon_hash"
  info "  Icon hash: $icon_hash"

  jq -n \
    --arg version "$version" \
    --arg rev "$tag" \
    --arg url "$url" \
    --arg hash "$hash" \
    --arg icon_url "$icon_url" \
    --arg icon_hash "$icon_hash" \
    '{version: $version, rev: $rev, url: $url, hash: $hash, icon: {url: $icon_url, hash: $icon_hash}}' \
    | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
