#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl jq nix git python3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIN_JSON="$SCRIPT_DIR/prerelease/prerelease.json"
TMP_DIR=$(mktemp -d)
PIN_TMP=""

OWNER="shadps4-emu"
REPO="shadPS4"
GITHUB_API="https://api.github.com/repos/$OWNER/$REPO"

# Upstream tags every prerelease Pre-release-shadPS4-<YYYY-MM-DD>-<40-char sha>.
TAG_PREFIX="Pre-release-shadPS4-"

# nixpkgs lib.fakeHash: valid but wrong, to provoke the mismatch that reveals the real one.
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

info()  { echo "==> $1"; }
error() { echo "ERROR: $1" >&2; exit 1; }

# Interpolated into a Nix --expr string, so reject chars that could break it. A variable
# because bash 5.3 no longer parses the escaped quote inline.
UNSAFE_SCRIPT_DIR_CHARS='[\\"{}[:cntrl:]]'
if [[ "$SCRIPT_DIR" =~ $UNSAFE_SCRIPT_DIR_CHARS ]]; then
  error "unsafe SCRIPT_DIR: $SCRIPT_DIR"
fi

# Restore pins on failure. Each updater clears its own backup on success, so the
# trap restores only what was touched, with no dynamic scoping of the pin path.
restore_pin() {
  local pin="$1" backup="$2"
  if [ -f "$backup" ]; then
    cp "$backup" "$SCRIPT_DIR/$pin"
    echo "  Restored previous $pin" >&2
  fi
}
trap 'restore_pin "prerelease/prerelease.json" "$TMP_DIR/pin-prerelease.bak"
      restore_pin "shadnet/shadnet.json" "$TMP_DIR/pin-shadnet.bak"
      [ -n "${PIN_TMP:-}" ] && rm -f "$PIN_TMP"
      rm -rf "$TMP_DIR"' EXIT

# Unauthenticated is 60 req/h per IP; CI passes GITHUB_TOKEN.
gh_api() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -sf -H "Authorization: Bearer $GITHUB_TOKEN" "$1"
  else
    curl -sf "$1"
  fi
}

# Writes the {version, rev, hash} pin atomically (temp + mv), so a crash cannot tear it.
write_pin() {
  local pin_json="$1" version="$2" rev="$3" hash="$4"
  if [ -z "$version" ] || [ -z "$rev" ] || [ -z "$hash" ] || [ -z "$pin_json" ]; then
    error "refusing to write an incomplete pin (file='$pin_json' version='$version' rev='$rev' hash='$hash')"
  fi
  # Exact SRI shape, so a mangled compute_hash capture fails here, not at build time.
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

# Builds the overlay's own src and reads the real hash from the mismatch the placeholder
# provokes. Not prefetchable from a tarball.
compute_hash() {
  local overlay="${1:-}"
  [ -n "$overlay" ] || overlay="prerelease/prerelease.nix"
  local out

  # GitHub throttles unauthenticated git traffic per IP and answers a blocked clone with
  # HTTP 401, which git reports as "could not read Username for 'https://github.com'".
  # The overlays pin http.version=HTTP/1.1, which is not throttled, but the fetcher
  # itself can still be refused, so retry with a growing delay before giving up.
  local attempt delay=30
  for attempt in 1 2 3 4; do
    out=$(cd "$SCRIPT_DIR" && nix build --impure --no-link --expr "
      (import <nixpkgs> {
        overlays = (import ./$overlay).nixpkgs.overlays;
      }).shadps4.src" 2>&1) && break
    # Only a transport failure is worth retrying; a build or eval error will not heal.
    if ! grep -q "could not read Username" <<<"$out"; then
      break
    fi
    if [ "$attempt" -lt 4 ]; then
      echo "  git transport refused by GitHub, retrying in ${delay}s ($attempt/4)" >&2
      sleep "$delay"
      delay=$((delay * 2))
    fi
  done
  out="${out:-}"

  # || true: under pipefail a grep miss would kill the caller before it can report.
  # Empty hash -> dump the full nix output so a real fetch failure is visible in CI.
  local hash
  hash=$(echo "$out" | grep -oP 'got:\s+\K\S+' | tail -1 || true)
  [ -n "$hash" ] || echo "$out" >&2
  echo "$hash"
}

# shadp2p = shadPS4 fork with the P2P client. Kept separate from the upstream prerelease
# to match the shadnet-p2p server pair.
update_shadnet() {
  local force="$1"
  local OWNER="Wozzardman" REPO="shadp2p"
  local GITHUB_API="https://api.github.com/repos/$OWNER/$REPO"
  local TAG_PREFIX="Pre-release-shadPS4-"
  local PIN_JSON="$SCRIPT_DIR/shadnet/shadnet.json"

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
  hash=$(compute_hash shadnet/shadnet.nix)
  [ -z "$hash" ] && error "Could not determine source hash for $rev"
  info "  Hash: $hash"

  write_pin "$PIN_JSON" "$version" "$rev" "$hash"
  rm -f "$TMP_DIR/pin-shadnet.bak"
  info "  shadnet fork updated: $version"
}

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

  # Pin the commit, not the tag: tags get replaced while the commit stays reachable.
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


# Upstream refactors the same files the fork touched, so these conflicts recur on
# every later pin. Each entry re-applies the fork's delta onto upstream's new shape.
resolve_known_conflicts() {
  local unmerged
  unmerged=$(git ls-files -u | cut -f2 | sort -u)
  [ -n "$unmerged" ] || return 0

  # stubs.cpp: upstream moved the nid lookup from the stub_nids[] table into
  # CommonStub, so re-apply the fork's Bloodborne fire-and-forget NID there.
  if printf '%s\n' "$unmerged" | grep -qx 'src/core/aerolib/stubs.cpp'; then
    info "  resolving src/core/aerolib/stubs.cpp (upstream stub-table refactor)"
    git checkout --ours src/core/aerolib/stubs.cpp
    # Explicit if !: set -e is inert in a `||` left-operand subshell, so a failed
    # resolver would be ignored and the patch would ship without the fork's delta.
    if ! python3 - src/core/aerolib/stubs.cpp <<'PY'
import sys

path = sys.argv[1]
src = open(path).read()

def need(text, anchor, what):
    # Not assert: PYTHONOPTIMIZE strips asserts, so a moved anchor would pass.
    if text.count(anchor) != 1:
        sys.exit(f'{what}: matched {text.count(anchor)} times, expected 1')

inc_anchor = '#include "core/aerolib/stubs.h"\n'
if '#include <string_view>' not in src:
    need(src, inc_anchor, 'stubs.h include anchor')
    src = src.replace(inc_anchor, inc_anchor + '\n#include <string_view>\n')

anchor = """    if (e.nid) {
        LOG_ERROR(Core, "Stub: {} (nid: {}) called, returning zero to {}", e.nid->name, e.nid->nid,"""
nid_case = """    if (e.nid != nullptr && std::string_view{e.nid->nid} == "Gaxrp3EWY-M") {
        // Bloodborne submits this fire-and-forget Plus notification every frame.
        LOG_TRACE(Core, "Stub: {} (nid: {}) called, returning zero to {}", e.nid->name, e.nid->nid,
                  __builtin_return_address(0));
        return 0;
    }
"""
# Keyed on the installed case, not the bare nid, which upstream may mention elsewhere.
if nid_case not in src:
    need(src, anchor, 'CommonStub nid anchor')
    src = src.replace(anchor, nid_case + anchor)

open(path, 'w').write(src)
PY
    then
      error "stubs.cpp conflict resolution failed (anchor moved upstream?)"
    fi
    # Post-condition: the fork's case must really be in the file, not merely exit 0.
    if ! grep -q 'e.nid != nullptr && std::string_view{e.nid->nid} == "Gaxrp3EWY-M"' \
      src/core/aerolib/stubs.cpp; then
      error "stubs.cpp resolution did not install the Gaxrp3EWY-M case"
    fi
    git add src/core/aerolib/stubs.cpp
  fi

  # module.cpp: upstream moved the eboot detection above the static-patching block and
  # widened it to any .elf, so the fork's Bloodborne calls land in a rewritten function.
  if printf '%s\n' "$unmerged" | grep -qx 'src/core/module.cpp'; then
    info "  resolving src/core/module.cpp (upstream moved the eboot detection)"
    git checkout --ours src/core/module.cpp
    if ! python3 - src/core/module.cpp <<'PY'
import sys

path = sys.argv[1]
src = open(path).read()

def need(text, anchor, what):
    # Not assert: PYTHONOPTIMIZE strips asserts, so a moved anchor would pass.
    if text.count(anchor) != 1:
        sys.exit(f'{what}: matched {text.count(anchor)} times, expected 1')

inc_anchor = '#include "core/aerolib/aerolib.h"\n'
if '#include "core/bloodborne_re.h"' not in src:
    need(src, inc_anchor, 'aerolib.h include anchor')
    src = src.replace(inc_anchor, inc_anchor + '#include "core/bloodborne_re.h"\n')

anchor = """            MemoryPatcher::g_eboot_name = name;
            MemoryPatcher::OnGameLoaded();
"""
nid_case = """#ifdef ARCH_X86_64
            // Bloodborne submits this fire-and-forget Plus notification every frame.
            Bloodborne::InstallSeamlessCoopPatches();
            Bloodborne::InstallReverseEngineeringTrace();
#endif
"""
if nid_case not in src:
    need(src, anchor, 'OnGameLoaded anchor')
    src = src.replace(anchor, anchor + nid_case)

open(path, 'w').write(src)
PY
    then
      error "module.cpp conflict resolution failed (anchor moved upstream?)"
    fi
    if ! grep -q 'Bloodborne::InstallSeamlessCoopPatches();' src/core/module.cpp; then
      error "module.cpp resolution did not install the Bloodborne patches"
    fi
    git add src/core/module.cpp
  fi
}

# The union merge keeps upstream's later UserSettings.Load() next to the fork's early
# one, and that reload drops the in-memory --user-id override. Remove the later loads.
fix_union_main() {
  if ! python3 - src/main.cpp <<'PY'
import sys

path = sys.argv[1]
src = open(path).read()
override = 'UserManagement.SetDefaultUserForProcess('
load = '    UserSettings.Load();\n'

if src.count(override) != 1:
    sys.exit(f'--user-id override: matched {src.count(override)} times, expected 1')
head, tail = src.split(override)
if load not in head:
    sys.exit('no UserSettings.Load() before the --user-id override')
open(path, 'w').write(head + override + tail.replace(load, ''))
PY
  then
    error "main.cpp union fix-up failed (override moved upstream?)"
  fi
}

# Rebuild shadnet-merge.patch = pinned prerelease tree + the fork's P2P delta, by a real
# 3-way merge so the delta tracks moving pins. Only used when both options are on.
gen_merge_patch() {
  local pre_rev fork_rev base_rev fork_used
  pre_rev=$(jq -r '.rev // ""' "$SCRIPT_DIR/prerelease/prerelease.json")
  fork_rev=$(jq -r '.rev // ""' "$SCRIPT_DIR/shadnet/shadnet.json")
  [ -n "$pre_rev" ] && [ -n "$fork_rev" ] || return 0
  local meta="$SCRIPT_DIR/shadnet/shadnet-merge.json"
  base_rev=$(jq -r '.baseRev // ""' "$meta" 2>/dev/null || echo "")
  fork_used=$(jq -r '.forkRev // ""' "$meta" 2>/dev/null || echo "")

  if [ "$base_rev" = "$pre_rev" ] && [ "$fork_used" = "$fork_rev" ]; then
    info "  merge patch up to date ($pre_rev + $fork_rev)"
    return 0
  fi

  info "  regenerating shadnet-merge.patch (prerelease $pre_rev + fork $fork_rev)..."
  # Work under $TMP_DIR so the EXIT trap cleans up on error, and stage the outputs in
  # temp files that only mv into place after a verified merge.
  local work="$TMP_DIR/merge"
  mkdir -p "$work"
  local patch_out="$TMP_DIR/shadnet-merge.patch.new"
  local meta_out="$TMP_DIR/shadnet-merge.json.new"

  git clone -q https://github.com/Wozzardman/shadp2p.git "$work/fork"
  # Fetch the prerelease base with enough history to reach the merge-base.
  git -C "$work/fork" fetch -q --depth=2000 \
    https://github.com/shadps4-emu/shadPS4.git "$pre_rev"
  git -C "$work/fork" worktree add -f "$work/wt" "$pre_rev" >/dev/null

  # Union-merge main.cpp, where both sides add independent flags: a same-line clash just
  # duplicates it for the build gate to reject. The attr is untracked, so it never ships.
  # The CI runner has no git identity yet, and git merge needs one even under --no-commit.
  git -C "$work/wt" config user.name "Icedos module updater"
  git -C "$work/wt" config user.email "modules-update@icedos.local"
  echo 'src/main.cpp merge=union' > "$work/wt/.gitattributes"
  (cd "$work/wt" && git merge --no-commit --no-ff "$fork_rev") || true
  rm -f "$work/wt/.gitattributes"
  (
    cd "$work/wt"
    local unmerged
    unmerged=$(git ls-files -u | cut -f2 | sort -u)
    if [ -n "$unmerged" ]; then
      # README.md is a doc, the fork side wins.
      if printf '%s\n' "$unmerged" | grep -qx 'README.md'; then
        git checkout --theirs README.md
        git add README.md
      fi
      unmerged=$(git ls-files -u | cut -f2 | sort -u)
    fi
    # Anything still unmerged has no known resolution, so a human must merge it.
    resolve_known_conflicts
    local still_unmerged
    still_unmerged=$(git ls-files -u | cut -f2 | sort -u)
    if [ -n "$still_unmerged" ]; then
      echo "ERROR: unresolved conflicts with no known resolution after merge:" >&2
      git status --porcelain | grep -E '^(UU|AA|DD)' >&2
      exit 1
    fi
    fix_union_main
    git add -A
    # Only what gets compiled; docs, CI, tests and RE scripts stay out.
    git diff --binary "$pre_rev" -- src CMakeLists.txt > "$work/merge.patch"
  ) || error "shadnet merge worktree step failed"

  if [ ! -s "$work/merge.patch" ]; then
    error "generated merge patch is empty - refusing to ship it"
  fi
  mv "$work/merge.patch" "$patch_out"
  jq -n --arg b "$pre_rev" --arg f "$fork_rev" '{baseRev: $b, forkRev: $f}' > "$meta_out"
  mv "$patch_out" "$SCRIPT_DIR/patches/shadnet-merge.patch"
  mv "$meta_out" "$meta"
  info "  wrote shadnet-merge.patch"
}

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
