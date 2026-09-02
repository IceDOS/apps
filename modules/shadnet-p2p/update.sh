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
OWNER="Wozzardman"
REPO="shadnet-p2p"
GITHUB_API="https://api.github.com/repos/$OWNER/$REPO"
TAG_PREFIX="pre-release-shadnet-"

main() {
  banner "shadnet-p2p updater"

  # Upstream only ships prereleases, so the normal gh_latest_release (which skips them)
  # would find nothing; grab the newest prerelease directly.
  info "Finding latest $OWNER/$REPO prerelease..."
  local tag
  tag=$(gh_api "$GITHUB_API/releases?per_page=100" \
    | jq -r '[.[] | select((.prerelease) and ((.draft | not))) ] | first | .tag_name // ""')
  [ -n "$tag" ] || error "no prerelease found"
  info "  Latest: $tag"

  # Tags are `pre-release-shadnet-<YYYY-MM-DD>-<40sha>`; the sha is the fetch rev.
  local rest="${tag#"$TAG_PREFIX"}"
  local rev="${rest##*-}"
  local date_part="${rest%-*}"
  [[ "$rev" =~ ^[0-9a-f]{40}$ ]] || error "could not parse a commit sha out of tag: $tag"
  local version="$date_part-${rev:0:7}"

  local current
  current=$(read_pin "$PIN" .rev)
  if [ "$rev" = "$current" ]; then
    info "  Already up to date ($version)"
    return
  fi
  info "  Current: ${current:-none}"

  # fetchSubmodules=true, so the hash must come from a real clone (see bb-launcher).
  info "  Computing hash (clones the repo + submodules, this takes a while)..."
  local hash
  hash=$(prefetch_git "https://github.com/$OWNER/$REPO" "$rev" --fetch-submodules || echo "")
  require_nonempty shadnet-p2p "$version" "$rev" "$hash"
  info "  Hash: $hash"

  jq -n --arg version "$version" --arg rev "$rev" --arg hash "$hash" \
    '{version: $version, rev: $rev, hash: $hash}' | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
