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
REPO="maxrave-dev/SimpMusic"
ASSET="SimpMusic-x86_64.AppImage"

main() {
  banner "simpmusic updater"

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

  local version="${tag#v}"

  # The asset name is version-less, so it is resolved from the release rather than
  # constructed — a rename shows up as "asset not found" instead of a silent 404.
  info "  Resolving $ASSET..."
  local url
  url=$(gh_release_asset_url "$REPO" "$tag" "^${ASSET}\$")
  [ -n "$url" ] || error "release $tag has no asset named $ASSET"

  info "  Computing hash..."
  local hash
  hash=$(prefetch_file "$url" || echo "")
  require_nonempty simpmusic "$version" "$tag" "$url" "$hash"
  info "  Hash: $hash"

  jq -n --arg version "$version" --arg rev "$tag" --arg url "$url" --arg hash "$hash" \
    '{version: $version, rev: $rev, url: $url, hash: $hash}' | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
