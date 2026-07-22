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
REPO="KRTirtho/spotube"
ASSET="Spotube-linux-x86_64.deb"

# Upstream replaces one rolling `nightly` release in place rather than cutting a new tag,
# so the tag is fixed and the asset is re-uploaded under the same name.
TAG="nightly"

main() {
  banner "spotube nightly updater"

  info "Reading the $TAG release..."
  local release
  release=$(gh_api "https://api.github.com/repos/$REPO/releases/tags/$TAG") \
    || error "failed to read the $TAG release"

  local url date
  url=$(echo "$release" | jq -r --arg n "$ASSET" \
    '[.assets[] | select(.name == $n)] | first | .browser_download_url // ""')
  [ -n "$url" ] || error "the $TAG release has no asset named $ASSET"

  # There is no version string to track, so the asset's own upload time stands in — it
  # moves on every re-upload, which is exactly when the hash changes.
  date=$(echo "$release" | jq -r --arg n "$ASSET" \
    '[.assets[] | select(.name == $n)] | first | .updated_at // ""' | cut -d'T' -f1)
  [ -n "$date" ] || error "could not read the upload date of $ASSET"

  local version="nightly-$date"
  info "  Latest: $version"

  info "  Computing hash..."
  local hash
  hash=$(prefetch_file "$url" || echo "")
  require_nonempty spotube "$version" "$url" "$hash"
  info "  Hash: $hash"

  # The hash is the real change signal: a re-upload with identical bytes should not churn
  # the pin, even though its date moved.
  local current
  current=$(read_pin "$PIN" .hash)
  if [ "$hash" = "$current" ]; then
    info "  Already up to date"
    return
  fi
  info "  Current: ${current:-none}"

  jq -n --arg version "$version" --arg url "$url" --arg hash "$hash" \
    '{version: $version, url: $url, hash: $hash}' | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
