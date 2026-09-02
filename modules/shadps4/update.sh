#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl jq nix git

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIN_JSON="$SCRIPT_DIR/prerelease.json"
TMP_DIR=$(mktemp -d)
PIN_TMP=""

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

# Restore the original pins on failure. Each updater backs up its own pin to a
# per-pin backup file and clears it on success, so the trap restores exactly
# what was touched - no bash dynamic-scoping of the pin path.
restore_pin() {
  local pin="$1" backup="$2"
  if [ -f "$backup" ]; then
    cp "$backup" "$SCRIPT_DIR/$pin"
    echo "  Restored previous $pin" >&2
  fi
}
trap 'restore_pin "prerelease.json" "$TMP_DIR/pin-prerelease.bak"
      restore_pin "shadnet.json" "$TMP_DIR/pin-shadnet.bak"
      [ -n "${PIN_TMP:-}" ] && rm -f "$PIN_TMP"
      rm -rf "$TMP_DIR"' EXIT

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
  local pin_json="$1" version="$2" rev="$3" hash="$4"
  if [ -z "$version" ] || [ -z "$rev" ] || [ -z "$hash" ] || [ -z "$pin_json" ]; then
    error "refusing to write an incomplete pin (file='$pin_json' version='$version' rev='$rev' hash='$hash')"
  fi
  # Require exact SRI shape so a mangled compute_hash capture fails here instead of at build time.
  if [[ ! "$hash" =~ ^sha256-[A-Za-z0-9+/]{43}=$ ]]; then
    error "refusing to write a malformed hash: '$hash'"
  fi
  # Same-directory mktemp so the final mv is a same-filesystem atomic rename.
  local tmp
  tmp=$(mktemp -p "$(dirname "$pin_json")")
  PIN_TMP="$tmp"
  jq -n --arg version "$version" --arg rev "$rev" --arg hash "$hash" \
    '{version: $version, rev: $rev, hash: $hash}' > "$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$pin_json"
  PIN_TMP=""
}

# Builds the overlay's own src (same expression the module uses) and reads the real
# hash from the mismatch the placeholder provokes. Not prefetchable from a tarball.
compute_hash() {
  local overlay="${1:-}"
  [ -n "$overlay" ] || overlay="prerelease.nix"
  local out
  out=$(cd "$SCRIPT_DIR" && nix build --impure --no-link --expr "
    (import <nixpkgs> {
      overlays = (import ./$overlay).nixpkgs.overlays;
    }).shadps4.src" 2>&1 || true)

  echo "$out" | grep -oP 'got:\s+\K\S+' | tail -1
}

# Update the shadnet fork pin (shadp2p = shadPS4 fork with the P2P client).
# Kept separate from the upstream prerelease; matches the shadnet-p2p server pair.
update_shadnet() {
  local force="$1"
  local OWNER="Wozzardman" REPO="shadp2p"
  local GITHUB_API="https://api.github.com/repos/$OWNER/$REPO"
  local TAG_PREFIX="Pre-release-shadPS4-"
  local PIN_JSON="$SCRIPT_DIR/shadnet.json"

  info "Finding latest $OWNER/$REPO fork prerelease..."
  local tag
  tag=$(gh_api "$GITHUB_API/releases?per_page=40" \
    | jq -r '[.[] | select(.prerelease and (.draft | not))] | first | .tag_name // ""') \
    || error "Failed to query GitHub releases"

  [ -z "$tag" ] && error "No fork prerelease found"
  info "  Latest fork prerelease: $tag"

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
  info "  Computing hash (clones the fork + submodules, this takes a while)..."

  [ -f "$PIN_JSON" ] && cp "$PIN_JSON" "$TMP_DIR/pin-shadnet.bak"
  write_pin "$PIN_JSON" "$version" "$rev" "$FAKE_HASH"

  local hash
  hash=$(compute_hash shadnet.nix)
  [ -z "$hash" ] && error "Could not determine source hash for $rev"
  info "  Hash: $hash"

  write_pin "$PIN_JSON" "$version" "$rev" "$hash"
  rm -f "$TMP_DIR/pin-shadnet.bak"
  info "  shadnet fork updated: $version"
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

  [ -f "$PIN_JSON" ] && cp "$PIN_JSON" "$TMP_DIR/pin-prerelease.bak"
  write_pin "$PIN_JSON" "$version" "$rev" "$FAKE_HASH"

  local hash
  hash=$(compute_hash)
  [ -z "$hash" ] && error "Could not determine source hash for $rev"
  info "  Hash: $hash"

  write_pin "$PIN_JSON" "$version" "$rev" "$hash"
  rm -f "$TMP_DIR/pin-prerelease.bak"
  info "  Prerelease updated: $version"
}


# Rebuild shadnet-merge.patch = pinned prerelease tree + the fork's P2P delta
# (a real 3-way merge). Done in CI/update so the merge tracks moving pins; the
# patch is only used when BOTH prerelease and shadnet are enabled.
gen_merge_patch() {
  local pre_rev fork_rev base_rev fork_used
  pre_rev=$(jq -r '.rev // ""' "$SCRIPT_DIR/prerelease.json")
  fork_rev=$(jq -r '.rev // ""' "$SCRIPT_DIR/shadnet.json")
  [ -n "$pre_rev" ] && [ -n "$fork_rev" ] || return 0
  local meta="$SCRIPT_DIR/shadnet-merge.json"
  base_rev=$(jq -r '.baseRev // ""' "$meta" 2>/dev/null || echo "")
  fork_used=$(jq -r '.forkRev // ""' "$meta" 2>/dev/null || echo "")

  if [ "$base_rev" = "$pre_rev" ] && [ "$fork_used" = "$fork_rev" ]; then
    info "  merge patch up to date ($pre_rev + $fork_rev)"
    return 0
  fi

  info "  regenerating shadnet-merge.patch (prerelease $pre_rev + fork $fork_rev)..."
  # Work under $TMP_DIR so the EXIT trap cleans up even on error, and write the
  # patch/metadata to temp files that only mv into place after a verified merge.
  local work="$TMP_DIR/merge"
  mkdir -p "$work"
  local patch_out="$TMP_DIR/shadnet-merge.patch.new"
  local meta_out="$TMP_DIR/shadnet-merge.json.new"

  git clone -q https://github.com/Wozzardman/shadp2p.git "$work/fork"
  # Fetch the prerelease base with enough history to reach the merge-base.
  git -C "$work/fork" fetch -q --depth=2000 \
    https://github.com/shadps4-emu/shadPS4.git "$pre_rev"
  local base
  base=$(git -C "$work/fork" merge-base "$fork_rev" "$pre_rev")
  git -C "$work/fork" diff "$base" "$fork_rev" > "$work/delta.patch"
  git -C "$work/fork" worktree add -f "$work/wt" "$pre_rev" >/dev/null

  # git apply --3way exits nonzero on conflict - that is expected (README.md is
  # the one known conflict). The verification below is what makes it safe: every
  # unmerged path other than README.md is fatal, and an empty result is fatal.
  (cd "$work/wt" && git apply --3way "$work/delta.patch") || true
  (
    cd "$work/wt"
    local unmerged
    unmerged=$(git ls-files -u | cut -f2 | sort -u)
    if [ -n "$unmerged" ] && [ "$unmerged" != "README.md" ]; then
      echo "ERROR: unresolved conflicts other than README.md after 3-way apply:" >&2
      git status --porcelain | grep -E '^(UU|AA|DD)' >&2
      exit 1
    fi
    if [ "$unmerged" = "README.md" ]; then
      # The one tolerated conflict: README.md is a doc, take the fork side.
      git checkout --theirs README.md
      git add README.md
    fi
    git add -A
    git diff --binary "$pre_rev" -- . > "$work/merge.patch"
  ) || error "shadnet merge worktree step failed"

  if [ ! -s "$work/merge.patch" ]; then
    error "generated merge patch is empty - refusing to ship it"
  fi
  mv "$work/merge.patch" "$patch_out"
  jq -n --arg b "$pre_rev" --arg f "$fork_rev" '{baseRev: $b, forkRev: $f}' > "$meta_out"
  mv "$patch_out" "$SCRIPT_DIR/shadnet-merge.patch"
  mv "$meta_out" "$meta"
  info "  wrote shadnet-merge.patch"
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
  update_shadnet "$force"
  gen_merge_patch

  echo ""
  info "Done. Review changes with: git diff $SCRIPT_DIR"
}

main "$@"
