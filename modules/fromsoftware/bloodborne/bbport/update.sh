#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl git jq nix

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
REPO="deadinside28/bloodborne_pc"
ASSET="Bloodborne-bbport-x86_64.AppImage"

# Newest non-draft release of any kind, so the prerelease channel also moves to a
# stable release that is newer than the last prerelease.
latest_any_release() {
  gh_api "https://api.github.com/repos/$REPO/releases?per_page=20" \
    | jq -r '[.[] | select(.draft | not)] | first | .tag_name // ""'
}

# SRI hash of the AppImage. Upstream's SHA256SUMS spares CI a ~400 MB download;
# releases without it fall back to hashing the file.
asset_hash() {
  local tag="$1" url="$2" sums_url hex=""

  sums_url=$(gh_release_asset_url "$REPO" "$tag" '^SHA256SUMS$')
  if [ -n "$sums_url" ]; then
    hex=$(curl -sfL "$sums_url" | awk -v f="$ASSET" '$2 == f || $2 == "*" f { print $1 }')
  fi

  if [ -n "$hex" ]; then
    to_sri "$hex"
  else
    prefetch_file "$url"
  fi
}

# update_channel CHANNEL TAG — pins TAG under .CHANNEL in source.json.
update_channel() {
  local channel="$1" tag="$2"

  info "[$channel] Latest: $tag"

  local current
  current=$(read_pin "$PIN" ".$channel.rev")
  if [ "$tag" = "$current" ]; then
    info "  Already up to date ($tag)"
    return
  fi
  info "  Current: ${current:-none}"

  local url
  url=$(gh_release_asset_url "$REPO" "$tag" "^${ASSET}\$")
  [ -n "$url" ] || error "release $tag has no asset named $ASSET"

  info "  Computing hash..."
  local hash
  hash=$(asset_hash "$tag" "$url" || echo "")
  require_nonempty "bbport ($channel)" "$tag" "$url" "$hash"
  info "  Hash: $hash"

  local pin='{}'
  [ -f "$PIN" ] && pin=$(cat "$PIN")
  jq --arg channel "$channel" --arg version "$tag" --arg rev "$tag" --arg url "$url" --arg hash "$hash" \
    '.[$channel] = {version: $version, rev: $rev, url: $url, hash: $hash}' <<<"$pin" | write_pin "$PIN"

  info "  Updated: $tag"
}

main() {
  banner "bbport updater"

  info "Finding latest $REPO releases..."
  local stable prerelease
  stable=$(gh_latest_release "$REPO")
  [ -n "$stable" ] || error "no stable release found"
  prerelease=$(latest_any_release)
  [ -n "$prerelease" ] || error "no release found"

  update_channel stable "$stable"
  update_channel prerelease "$prerelease"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
