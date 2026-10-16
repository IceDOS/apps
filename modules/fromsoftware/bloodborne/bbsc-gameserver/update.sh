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
OWNER="deadinside28"
REPO="bloodborne_pc"

main() {
  banner "bbsc-gameserver updater"

  # Newest non-draft release of any kind: the BBSC client code only ships in bbport
  # prereleases so far, and the server must speak the same relay protocol.
  info "Finding latest $OWNER/$REPO release..."
  local tag
  tag=$(gh_api "https://api.github.com/repos/$OWNER/$REPO/releases?per_page=20" \
    | jq -r '[.[] | select(.draft | not)] | first | .tag_name // ""')
  [ -n "$tag" ] || error "no release found"
  info "  Latest: $tag"

  local current
  current=$(read_pin "$PIN" .rev)
  if [ "$tag" = "$current" ]; then
    info "  Already up to date ($tag)"
    return
  fi
  info "  Current: ${current:-none}"

  info "  Computing hash..."
  local hash
  hash=$(prefetch_github "$OWNER" "$REPO" "$tag" || echo "")
  require_nonempty bbsc-gameserver "$tag" "$tag" "$hash"
  info "  Hash: $hash"

  jq -n --arg version "$tag" --arg rev "$tag" --arg hash "$hash" \
    '{version: $version, rev: $rev, hash: $hash}' | write_pin "$PIN"

  info "  Updated: $tag"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
