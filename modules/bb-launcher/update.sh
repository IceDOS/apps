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
REPO="rainmakerv3/BB_Launcher"

main() {
  banner "bb-launcher updater"

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

  # Tags are `Release<ver>`, e.g. Release16.04 -> 16.04.
  local version="${tag#Release}"

  # The derivation sets `fetchSubmodules = true`, and the GitHub archive tarball contains
  # no submodule content — so the hash has to come from a real clone, not prefetch_github.
  info "  Computing hash (clones the repo + submodules, this takes a while)..."
  local hash
  hash=$(prefetch_git "https://github.com/$REPO" "refs/tags/$tag" --fetch-submodules || echo "")
  require_nonempty bb-launcher "$version" "$tag" "$hash"
  info "  Hash: $hash"

  jq -n --arg version "$version" --arg rev "$tag" --arg hash "$hash" \
    '{version: $version, rev: $rev, hash: $hash}' | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
