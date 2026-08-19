#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl jq nix

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIN_JSON="$SCRIPT_DIR/prerelease.json"
TMP_DIR=$(mktemp -d)

OWNER="shadps4-emu"
REPO="shadPS4"
GITHUB_API="https://api.github.com/repos/$OWNER/$REPO"

# Upstream tags every prerelease Pre-release-shadPS4-<YYYY-MM-DD>-<40-char sha>.
TAG_PREFIX="Pre-release-shadPS4-"

# nixpkgs lib.fakeHash — valid but wrong SRI hash to provoke the mismatch that reveals the real one.
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

info()  { echo "==> $1"; }
error() { echo "ERROR: $1" >&2; exit 1; }

# SCRIPT_DIR is interpolated into a Nix --expr string — reject chars that could break it.
# In a variable because bash 5.3 no longer parses the escaped quote inline.
UNSAFE_SCRIPT_DIR_CHARS='[\\"{}[:cntrl:]]'
if [[ "$SCRIPT_DIR" =~ $UNSAFE_SCRIPT_DIR_CHARS ]]; then
  error "unsafe SCRIPT_DIR: $SCRIPT_DIR"
fi

# Restore the original pin on failure; clear any temp pin write_pin left behind.
PIN_TMP=""
restore_pin() {
  if [ -f "$TMP_DIR/pin.bak" ]; then
    cp "$TMP_DIR/pin.bak" "$PIN_JSON"
    echo "  Restored previous $PIN_JSON" >&2
  fi
}
trap '[ -n "$PIN_TMP" ] && rm -f "$PIN_TMP"; restore_pin; rm -rf "$TMP_DIR"' EXIT

# --- GitHub API ---
# Unauthenticated is 60 req/h per IP; CI passes GITHUB_TOKEN.
gh_api() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -sf -H "Authorization: Bearer $GITHUB_TOKEN" "$1"
  else
    curl -sf "$1"
  fi
}

# --- Write the {version, rev, hash} pin ---
# Validates fields, writes atomically (temp + mv) so a crash can never leave a torn pin.
write_pin() {
  local version="$1" rev="$2" hash="$3"
  if [ -z "$version" ] || [ -z "$rev" ] || [ -z "$hash" ]; then
    error "refusing to write an incomplete pin (version='$version' rev='$rev' hash='$hash')"
  fi
  # Require exact SRI shape so a mangled compute_hash capture fails here instead of at build time.
  if [[ ! "$hash" =~ ^sha256-[A-Za-z0-9+/]{43}=$ ]]; then
    error "refusing to write a malformed hash: '$hash'"
  fi
  # Same-directory mktemp so the final mv is a same-filesystem atomic rename.
  PIN_TMP=$(mktemp -p "$(dirname "$PIN_JSON")")
  local tmp="$PIN_TMP"
  jq -n --arg version "$version" --arg rev "$rev" --arg hash "$hash" \
    '{version: $version, rev: $rev, hash: $hash}' > "$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$PIN_JSON"
  PIN_TMP=""
}

# Builds the overlay's own src (same expression the module uses) and reads the real
# hash from the mismatch the placeholder provokes. Not prefetchable from a tarball.
compute_hash() {
  local out
  out=$(cd "$SCRIPT_DIR" && nix build --impure --no-link --expr "
    (import <nixpkgs> {
      overlays = (import ./prerelease.nix).nixpkgs.overlays;
    }).shadps4.src" 2>&1 || true)

  echo "$out" | grep -oP 'got:\s+\K\S+' | tail -1
}

# --- Update the prerelease pin ---
# force=1 re-pins on an unchanged rev: the hash covers the whole src expression, so a
# prerelease.nix edit invalidates it while the rev stays put.
update_prerelease() {
  local force="$1"

  info "Finding latest shadPS4 prerelease..."

  local tag
  tag=$(gh_api "$GITHUB_API/releases?per_page=20" \
    | jq -r '[.[] | select(.prerelease and (.draft | not))] | first | .tag_name // ""') \
    || error "Failed to query GitHub releases"

  [ -z "$tag" ] && error "No prerelease found"
  info "  Latest prerelease: $tag"

  # Pin the commit, not the tag — tags get replaced while the commit stays reachable.
  local rest="${tag#"$TAG_PREFIX"}"
  local rev="${rest##*-}"
  local date_part="${rest%-*}"

  [[ "$rev" =~ ^[0-9a-f]{40}$ ]] || error "Could not parse a commit sha out of tag: $tag"

  local version="$date_part-${rev:0:7}"

  local current_rev
  current_rev=$(jq -r '.rev // ""' "$PIN_JSON" 2>/dev/null || echo "")

  if [ "$rev" = "$current_rev" ] && [ "$force" -eq 0 ]; then
    info "  Already up to date ($version)"
    return
  fi

  info "  Current: ${current_rev:-none}"
  info "  Computing hash (clones the repo + submodules, this takes a while)..."

  [ -f "$PIN_JSON" ] && cp "$PIN_JSON" "$TMP_DIR/pin.bak"
  write_pin "$version" "$rev" "$FAKE_HASH"

  local hash
  hash=$(compute_hash)
  [ -z "$hash" ] && error "Could not determine source hash for $rev"
  info "  Hash: $hash"

  write_pin "$version" "$rev" "$hash"
  rm -f "$TMP_DIR/pin.bak"
  info "  Prerelease updated: $version"
}

# --- Main ---
main() {
  local force=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=1 ;;
      *) error "unknown argument: $1 (usage: update.sh [--force])" ;;
    esac
    shift
  done

  echo "shadPS4 prerelease updater"
  echo "=========================="

  update_prerelease "$force"

  echo ""
  info "Done. Review changes with: git diff $SCRIPT_DIR"
}

main "$@"
