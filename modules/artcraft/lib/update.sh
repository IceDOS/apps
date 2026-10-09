#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl git jq nix

# Usage: update.sh <app>, e.g. update.sh photocraft. Rewrites modules/artcraft/<app>/source.json.
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

APP="${1:?usage: update.sh <app>}"
PIN="$(dirname "$SCRIPT_DIR")/$APP/source.json"
REPO="storytold/$APP"
ARCHES=(x86_64 aarch64)

[ -f "$PIN" ] || error "no pin at $PIN"

main() {
  banner "$APP updater"

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

  local version="${tag#v}"

  # Upstream publishes SHA256SUMS.txt per release, which saves downloading two ~60 MB
  # tarballs. fetchurl still checks the hash, so a wrong sum fails the build.
  info "  Reading SHA256SUMS.txt..."
  local sums_url sums
  sums_url=$(gh_release_asset_url "$REPO" "$tag" '^SHA256SUMS\.txt$')
  [ -n "$sums_url" ] || error "release $tag has no SHA256SUMS.txt"
  sums=$(curl -fsSL "$sums_url")

  local hashes='{}' arch file hex hash
  for arch in "${ARCHES[@]}"; do
    file="$APP-$version-linux-$arch.tar.gz"
    hex=$(awk -v f="$file" '$2 == f { print $1 }' <<<"$sums")
    [ -n "$hex" ] || error "release $tag has no checksum for $file (asset renamed?)"
    hash=$(to_sri "$hex" || echo "")
    require_nonempty "$APP" "$hash"
    info "  $arch: $hash"
    hashes=$(jq --arg k "$arch" --arg v "$hash" '.[$k] = $v' <<<"$hashes")
  done

  require_nonempty "$APP" "$version" "$tag"

  jq -n --arg version "$version" --arg rev "$tag" --argjson hashes "$hashes" \
    '{version: $version, rev: $rev, hashes: $hashes}' | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $(dirname "$PIN")"
