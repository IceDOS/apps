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
REPO="Minksh/ReignTweak"

main() {
  banner "reigntweak updater"

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

  # Tags are `Release<ver>`, except the older `ReleaseP1` prerelease which has no number.
  local version="${tag#Release}"

  # Upstream changed the asset from `reigntweak.tar.gz` to a bare `reigntweak` ELF at
  # Release1.2, so the URL is resolved from the release and stored in the pin. package.nix
  # expects the bare executable; a return to an archive would need it changed back.
  info "  Resolving release asset..."
  local url
  url=$(gh_release_asset_url "$REPO" "$tag" '^reigntweak$')
  [ -n "$url" ] || error "release $tag has no bare 'reigntweak' asset (did upstream go back to an archive?)"

  info "  Computing hash..."
  local hash
  hash=$(prefetch_file "$url" || echo "")
  require_nonempty reigntweak "$version" "$tag" "$url" "$hash"
  info "  Hash: $hash"

  jq -n --arg version "$version" --arg rev "$tag" --arg url "$url" --arg hash "$hash" \
    '{version: $version, rev: $rev, url: $url, hash: $hash}' | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
