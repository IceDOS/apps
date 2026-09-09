#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl git jq nix nix-prefetch-git npm-lockfile-fix prefetch-npm-deps

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
REPO="PrimeIntellect-ai/prime-agent"

main() {
  banner "prime-agent updater"

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

  # Upstream tags `vX.Y.Z`; the derivation's `version` carries no prefix.
  local version="${tag#v}"

  # global on purpose: the EXIT trap fires after main() returns,
  # where a `local` would already be out of scope (set -u)
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT

  git clone --depth 1 --branch "$tag" "https://github.com/$REPO.git" "$tmpdir/repo" 2>/dev/null
  # package.nix runs npm-lockfile-fix in fetchFromGitHub's postFetch, so the source
  # hash must cover the fixed tree: raw nix-prefetch-git hashes differ after the fix.
  npm-lockfile-fix "$tmpdir/repo/package-lock.json"
  rm -rf "$tmpdir/repo/.git"

  info "  Computing source hash (tree after npm-lockfile-fix)..."
  local hash
  hash=$(nix hash path "$tmpdir/repo" || echo "")
  require_nonempty prime-agent "$version" "$tag" "$hash"
  info "  Hash: $hash"

  # npmDepsHash from the same fixed lockfile: buildNpmPackage defaults to
  # NPM_FETCHER_VERSION=2 while prefetch-npm-deps defaults to v1, so set it.
  info "  Computing npmDepsHash..."
  local npmDepsHash
  npmDepsHash=$(NPM_FETCHER_VERSION=2 prefetch-npm-deps "$tmpdir/repo/package-lock.json" 2>/dev/null || echo "")
  require_nonempty prime-agent-npm "$version" "$tag" "$npmDepsHash"
  info "  npmDepsHash: $npmDepsHash"

  jq -n --arg version "$version" --arg rev "$tag" --arg hash "$hash" --arg npmDepsHash "$npmDepsHash" \
    '{version: $version, rev: $rev, hash: $hash, npmDepsHash: $npmDepsHash}' | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
