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
REPO="KytyPS5/KytyPS5"

main() {
  banner "kytyps5 updater"

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

  # Tags look like `KytyPS5-2026-10-04-719e025`; the version is the date part.
  local version="${tag#KytyPS5-}"

  # fetchSubmodules = true, so the hash must come from a real clone.
  info "  Computing hash (clones the repo + submodules, this takes a while)..."
  local hash
  hash=$(prefetch_git "https://github.com/$REPO" "refs/tags/$tag" --fetch-submodules || echo "")
  require_nonempty kytyps5 "$version" "$tag" "$hash"
  info "  Hash: $hash"

  # The emulator keys its Vulkan pipeline cache on the full commit, and the source has no .git.
  local commit
  # An annotated tag peels to its commit via ^{}; a lightweight tag points at it directly.
  commit=$(git ls-remote "https://github.com/$REPO" "refs/tags/$tag^{}" | cut -f1)
  [ -n "$commit" ] || commit=$(git ls-remote "https://github.com/$REPO" "refs/tags/$tag" | cut -f1)
  [ -n "$commit" ] || error "cannot resolve commit for $tag"

  # 3rdparty/ffmpeg-core downloads a prebuilt FFmpeg at configure time, so the build
  # needs that zip as a store path. Its rev is the ffmpeg-core submodule sha of src.
  local submodule_rev
  submodule_rev=$(gh_api "repos/$REPO/contents/3rdparty/ffmpeg-core?ref=$tag" | jq -r .sha)
  [ -n "$submodule_rev" ] && [ "$submodule_rev" != "null" ] || error "cannot resolve ffmpeg-core submodule"

  info "  ffmpeg-core rev: $submodule_rev"
  info "  Computing FFmpeg hash..."
  local ffmpeg_hash
  ffmpeg_hash=$(prefetch_file \
    "https://github.com/KytyPS5/ext-ffmpeg-core/releases/download/$submodule_rev/ffmpeg-linux-x64.zip")
  [ -n "$ffmpeg_hash" ] || error "cannot prefetch ffmpeg zip"

  jq -n --arg version "$version" --arg rev "$tag" --arg hash "$hash" \
        --arg ffmpegRev "$submodule_rev" --arg ffmpegHash "$ffmpeg_hash" --arg commit "$commit" \
    '{version: $version, rev: $rev, hash: $hash, ffmpegRev: $ffmpegRev, ffmpegHash: $ffmpegHash, commit: $commit}' \
    | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
