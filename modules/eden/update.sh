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

# Eden is hosted on its own Gitea instance, so none of the gh_* helpers apply — Gitea's
# v1 API is used directly. It needs no auth for public releases.
API="https://git.eden-emu.dev/api/v1/repos/eden-emu/eden"

# Every (build, toolchain) pair package.nix can be called with. All are pinned so that
# flipping `build` or `compiledWith` never lands on an unpinned asset.
BUILDS=(aarch64 amd64 legacy rog-ally steamdeck)
TOOLCHAINS=(clang-pgo gcc-standard)

main() {
  banner "eden updater"

  info "Finding latest Eden release..."
  local tag
  tag=$(curl -sf "$API/releases?limit=10" \
    | jq -r '[.[] | select((.draft | not) and (.prerelease | not))] | first | .tag_name // ""') \
    || error "failed to query the Gitea releases API"
  [ -n "$tag" ] || error "no release found"
  info "  Latest: $tag"

  local current
  current=$(read_pin "$PIN" .rev)
  if [ "$tag" = "$current" ]; then
    info "  Already up to date ($tag)"
    return
  fi
  info "  Current: ${current:-none}"

  local version="${tag#v}"

  # Resolve each asset from the release rather than constructing ten URLs: a build that
  # upstream stops publishing then fails here by name instead of 404-ing at build time.
  local assets
  assets=$(curl -sf "$API/releases/tags/$tag" | jq -c '[.assets[] | {name, url: .browser_download_url}]') \
    || error "failed to read the asset list for $tag"

  local builds_json="{}" build toolchain url hash
  for build in "${BUILDS[@]}"; do
    for toolchain in "${TOOLCHAINS[@]}"; do
      url=$(echo "$assets" \
        | jq -r --arg n "Eden-Linux-$tag-$build-$toolchain.AppImage" \
          '[.[] | select(.name == $n)] | first | .url // ""')
      [ -n "$url" ] || error "release $tag has no asset Eden-Linux-$tag-$build-$toolchain.AppImage"

      info "  Hashing $build/$toolchain..."
      hash=$(prefetch_file "$url" || echo "")
      require_nonempty "eden ($build/$toolchain)" "$url" "$hash"

      builds_json=$(echo "$builds_json" \
        | jq --arg b "$build" --arg t "$toolchain" --arg url "$url" --arg hash "$hash" \
          '.[$b][$t] = {url: $url, hash: $hash}')
    done
  done

  jq -n --arg version "$version" --arg rev "$tag" --argjson builds "$builds_json" \
    '{version: $version, rev: $rev, builds: $builds}' | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
