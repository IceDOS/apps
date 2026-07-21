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

# lib.fakeHash — a valid but wrong SRI hash, used to provoke the mismatch that
# reveals the real one.
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

info()  { echo "==> $1"; }
error() { echo "ERROR: $1" >&2; exit 1; }

# The pin is briefly written with a placeholder hash (see compute_hash); put the
# original back if anything goes wrong before the real hash lands.
restore_pin() {
  if [ -f "$TMP_DIR/pin.bak" ]; then
    cp "$TMP_DIR/pin.bak" "$PIN_JSON"
    echo "  Restored previous $PIN_JSON" >&2
  fi
}
trap 'restore_pin; rm -rf "$TMP_DIR"' EXIT

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
# A pin with an empty field still evaluates, producing a nameless derivation that
# fails deep in a build, so refuse to write one.
write_pin() {
  local version="$1" rev="$2" hash="$3"
  if [ -z "$version" ] || [ -z "$rev" ] || [ -z "$hash" ]; then
    error "refusing to write an incomplete pin (version='$version' rev='$rev' hash='$hash')"
  fi
  jq -n --arg version "$version" --arg rev "$rev" --arg hash "$hash" \
    '{version: $version, rev: $rev, hash: $hash}' > "$PIN_JSON"
}

# --- Compute the SRI hash of a shadps4 checkout ---
# The hash covers the git tree *after* the postCheckout hook in prerelease.nix has
# run (submodule init, generated COMMIT/SOURCE_DATE_EPOCH), so it can't be
# prefetched from a tarball. Build the overlay's own src — the same expression the
# module uses, so the two can never disagree — and read the right hash out of the
# mismatch the placeholder provokes.
compute_hash() {
  local out
  out=$(nix build --impure --no-link --expr "
    (import <nixpkgs> {
      overlays = (import $SCRIPT_DIR/prerelease.nix).nixpkgs.overlays;
    }).shadps4.src" 2>&1 || true)

  echo "$out" | grep -oP 'got:\s+\K\S+' | tail -1
}

# --- Update the prerelease pin ---
update_prerelease() {
  info "Finding latest shadPS4 prerelease..."

  local tag
  tag=$(gh_api "$GITHUB_API/releases?per_page=20" \
    | jq -r '[.[] | select(.prerelease and (.draft | not))] | first | .tag_name // ""') \
    || error "Failed to query GitHub releases"

  [ -z "$tag" ] && error "No prerelease found"
  info "  Latest prerelease: $tag"

  # Pin the commit, not the tag: the prerelease is replaced rather than added to, so
  # old tags get deleted while the commit stays reachable from main.
  local rest="${tag#"$TAG_PREFIX"}"
  local rev="${rest##*-}"
  local date_part="${rest%-*}"

  [[ "$rev" =~ ^[0-9a-f]{40}$ ]] || error "Could not parse a commit sha out of tag: $tag"

  local version="$date_part-${rev:0:7}"

  local current_rev
  current_rev=$(jq -r '.rev // ""' "$PIN_JSON" 2>/dev/null || echo "")

  if [ "$rev" = "$current_rev" ]; then
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
  echo "shadPS4 prerelease updater"
  echo "=========================="

  update_prerelease

  echo ""
  info "Done. Review changes with: git diff $SCRIPT_DIR"
}

main "$@"
