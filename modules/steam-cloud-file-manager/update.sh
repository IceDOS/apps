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
OWNER="Fldicoahkiin"
NAME="SteamCloudFileManager"
REPO="$OWNER/$NAME"

main() {
  banner "steam-cloud-file-manager updater"

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

  info "  Computing source hash..."
  local hash
  hash=$(prefetch_github "$OWNER" "$NAME" "$tag" || echo "")
  require_nonempty steam-cloud-file-manager "$version" "$tag" "$hash"
  info "  Hash: $hash"

  # No prefetcher exists for the cargo vendor dir, so build it with a fake hash
  # and read the real one from the mismatch error.
  info "  Computing cargoHash (vendors all crates, this takes a while)..."
  local cargoHash
  cargoHash=$(nix-build --no-out-link -E "
    with import <nixpkgs> { };
    rustPlatform.fetchCargoVendor {
      src = fetchFromGitHub {
        owner = \"$OWNER\";
        repo = \"$NAME\";
        rev = \"$tag\";
        hash = \"$hash\";
      };
      hash = lib.fakeHash;
    }" 2>&1 | sed -n 's/^ *got: *//p' || echo "")
  require_nonempty steam-cloud-file-manager-cargo "$version" "$tag" "$cargoHash"
  info "  cargoHash: $cargoHash"

  jq -n --arg version "$version" --arg rev "$tag" --arg hash "$hash" --arg cargoHash "$cargoHash" \
    '{version: $version, rev: $rev, hash: $hash, cargoHash: $cargoHash}' | write_pin "$PIN"

  info "  Updated: $version"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
