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
REPO="team-spotube/spotube"
ASSET="Spotube-linux-x86_64.deb"

# Upstream replaces one rolling `nightly` release in place rather than cutting a new tag,
# so the tag is fixed and the asset is re-uploaded under the same name.
TAG="nightly"

GIT_PIN="$SCRIPT_DIR/git.json"
GIT_DEPS="$SCRIPT_DIR/git-deps.json"
GIT_BRANCH="dev"

# nixpkgs lib.fakeHash: a valid SRI whose mismatch error reveals the real hash.
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

update_nightly() {
  banner "spotube nightly updater"

  info "Reading the $TAG release..."
  local release
  release=$(gh_api "https://api.github.com/repos/$REPO/releases/tags/$TAG") \
    || error "failed to read the $TAG release"

  local url date
  url=$(echo "$release" | jq -r --arg n "$ASSET" \
    '[.assets[] | select(.name == $n)] | first | .browser_download_url // ""')
  [ -n "$url" ] || error "the $TAG release has no asset named $ASSET"

  # There is no version string to track, so the asset's own upload time stands in — it
  # moves on every re-upload, which is exactly when the hash changes.
  date=$(echo "$release" | jq -r --arg n "$ASSET" \
    '[.assets[] | select(.name == $n)] | first | .updated_at // ""' | cut -d'T' -f1)
  [ -n "$date" ] || error "could not read the upload date of $ASSET"

  local version="nightly-$date"
  info "  Latest: $version"

  info "  Computing hash..."
  local hash
  hash=$(prefetch_file "$url" || echo "")
  require_nonempty spotube "$version" "$url" "$hash"
  info "  Hash: $hash"

  # The hash is the real change signal: a re-upload with identical bytes should not churn
  # the pin, even though its date moved.
  local current
  current=$(read_pin "$PIN" .hash)
  if [ "$hash" = "$current" ]; then
    info "  Already up to date"
    return
  fi
  info "  Current: ${current:-none}"

  jq -n --arg version "$version" --arg url "$url" --arg hash "$hash" \
    '{version: $version, url: $url, hash: $hash}' | write_pin "$PIN"

  info "  Updated: $version"
}

# fod_hash EXPR: builds a fixed-output derivation given with $FAKE_HASH and prints the
# hash from the mismatch. EXPR is evaluated inside `with import <nixpkgs> {}`.
fod_hash() {
  local out hash
  out=$(nix build --impure --no-link --expr "with import <nixpkgs> {}; $1" 2>&1 || true)
  hash=$(echo "$out" | grep -oP 'got:\s+\K\S+' | tail -1 || true)
  [ -n "$hash" ] || echo "$out" >&2
  echo "$hash"
}

# github_pin REPO: {rev, hash} of the default branch of a team-spotube gradle plugin.
github_pin() {
  local rev hash
  rev=$(git_head "https://github.com/team-spotube/$1.git")
  [ -n "$rev" ] || error "could not read the HEAD of team-spotube/$1"
  hash=$(prefetch_github team-spotube "$1" "$rev")
  require_nonempty "$1" "$rev" "$hash"
  jq -n --arg rev "$rev" --arg hash "$hash" '{rev: $rev, hash: $hash}'
}

# android_platform SDK: the androidenv platform name for compileSdk SDK, which the repo
# lists as "37.0" for newer releases and "36" for older ones.
android_platform() {
  nix eval --impure --raw --expr "
    let
      pkgs = import <nixpkgs> { };
      platforms = (pkgs.lib.importJSON \"\${pkgs.path}/pkgs/development/mobile/androidenv/repo.json\").packages.platforms;
    in
    if platforms ? \"$1.0\" then \"$1.0\" else \"$1\""
}

update_git() {
  banner "spotube git updater"

  info "Reading the $GIT_BRANCH branch..."
  local rev
  rev=$(git_head "https://github.com/$REPO.git" "$GIT_BRANCH")
  [ -n "$rev" ] || error "could not read the head of $GIT_BRANCH"
  info "  Latest: $rev"

  # The plugins have no pinned upstream version either, so their heads count as a change.
  local gradle_plugin vlcj_bundler
  gradle_plugin=$(github_pin gradle-plugin)
  vlcj_bundler=$(github_pin vlcj-bundler-gradle-plugin)

  if [ "$rev" = "$(read_pin "$GIT_PIN" .rev)" ] \
    && [ "$(jq -r .rev <<<"$gradle_plugin")" = "$(read_pin "$GIT_PIN" .gradlePlugin.rev)" ] \
    && [ "$(jq -r .rev <<<"$vlcj_bundler")" = "$(read_pin "$GIT_PIN" .vlcjBundler.rev)" ]; then
    info "  Already up to date"
    return
  fi

  local date version hash
  date=$(gh_api "https://api.github.com/repos/$REPO/commits/$rev" \
    | jq -r '.commit.committer.date // ""' | cut -d'T' -f1)
  [ -n "$date" ] || error "could not read the commit date of $rev"
  version="$date-${rev:0:7}"

  info "  Computing source hash..."
  hash=$(prefetch_github team-spotube spotube "$rev")
  require_nonempty spotube "$hash"

  local src="fetchFromGitHub { owner = \"team-spotube\"; repo = \"spotube\"; rev = \"$rev\"; hash = \"$hash\"; }"

  info "  Computing cargo vendor hash..."
  local cargo_hash
  cargo_hash=$(fod_hash "rustPlatform.fetchCargoVendor {
    src = $src;
    sourceRoot = \"source/composeApp\";
    hash = \"$FAKE_HASH\";
  }")
  require_nonempty "spotube cargo" "$cargo_hash"

  # gobley's bindgen is published with the same version as the gobley gradle plugins.
  local toml bindgen_version sdk platform
  toml=$(curl -sf "https://raw.githubusercontent.com/$REPO/$rev/gradle/libs.versions.toml") \
    || error "could not read libs.versions.toml at $rev"
  bindgen_version=$(echo "$toml" | grep -oP '^uniffi\s*=\s*"\K[^"]+' || true)
  sdk=$(echo "$toml" | grep -oP '^android-compileSdk\s*=\s*"\K[^"]+' || true)
  require_nonempty "spotube versions" "$bindgen_version" "$sdk"
  platform=$(android_platform "$sdk")

  local wrapper gradle_version gradle_hash
  wrapper=$(curl -sf "https://raw.githubusercontent.com/$REPO/$rev/gradle/wrapper/gradle-wrapper.properties") \
    || error "could not read gradle-wrapper.properties at $rev"
  gradle_version=$(echo "$wrapper" | grep -oP 'gradle-\K[0-9.]+(?=-(bin|all)\.zip)' || true)
  require_nonempty "gradle version" "$gradle_version"
  info "  Computing gradle $gradle_version hash..."
  gradle_hash=$(prefetch_file "https://services.gradle.org/distributions/gradle-$gradle_version-bin.zip" || echo "")
  require_nonempty "gradle" "$gradle_hash"

  info "  Computing gobley-uniffi-bindgen $bindgen_version hashes..."
  local crate="fetchCrate { pname = \"gobley-uniffi-bindgen\"; version = \"$bindgen_version\";"
  local bindgen_hash bindgen_cargo_hash
  bindgen_hash=$(fod_hash "$crate hash = \"$FAKE_HASH\"; }")
  require_nonempty "gobley-uniffi-bindgen" "$bindgen_hash"
  bindgen_cargo_hash=$(fod_hash "(rustPlatform.buildRustPackage {
    pname = \"gobley-uniffi-bindgen\";
    version = \"$bindgen_version\";
    src = $crate hash = \"$bindgen_hash\"; };
    cargoHash = \"$FAKE_HASH\";
  }).cargoDeps")
  require_nonempty "gobley-uniffi-bindgen cargo" "$bindgen_cargo_hash"

  # The deps refresh below evaluates git.nix against the new pin, so both files are
  # restored if it fails rather than leaving a pin without matching gradle deps.
  local backup
  backup=$(mktemp -d)
  cp "$GIT_PIN" "$GIT_DEPS" "$backup/"
  trap 'cp "'"$backup"'/git.json" "'"$GIT_PIN"'"; cp "'"$backup"'/git-deps.json" "'"$GIT_DEPS"'"' ERR

  jq -n \
    --arg version "$version" --arg rev "$rev" --arg hash "$hash" \
    --arg cargoHash "$cargo_hash" --arg androidPlatform "$platform" \
    --arg bindgenVersion "$bindgen_version" --arg bindgenHash "$bindgen_hash" \
    --arg bindgenCargoHash "$bindgen_cargo_hash" \
    --arg gradleVersion "$gradle_version" --arg gradleHash "$gradle_hash" \
    --argjson gradlePlugin "$gradle_plugin" --argjson vlcjBundler "$vlcj_bundler" \
    '{
      version: $version,
      rev: $rev,
      hash: $hash,
      cargoHash: $cargoHash,
      androidPlatform: $androidPlatform,
      gradle: {version: $gradleVersion, hash: $gradleHash},
      uniffiBindgen: {version: $bindgenVersion, hash: $bindgenHash, cargoHash: $bindgenCargoHash},
      gradlePlugin: $gradlePlugin,
      vlcjBundler: $vlcjBundler
    }' | write_pin "$GIT_PIN"

  info "  Pin: $(jq -c . "$GIT_PIN")"

  # Runs the real gradle build behind mitm-cache and records every artifact it fetches.
  info "  Refreshing gradle deps (runs the full build)..."
  local script
  script=$(nix build --impure --no-link --print-out-paths --expr "
    (import <nixpkgs> {
      config.allowUnfree = true;
      overlays = (import $SCRIPT_DIR/nightly.nix).nixpkgs.overlays
        ++ (import $SCRIPT_DIR/git.nix).nixpkgs.overlays;
    }).spotube.tree.mitmCache.updateScript")
  "$script"

  trap - ERR
  rm -rf "$backup"
  info "  Updated: $version"
}

main() {
  case "${1:-all}" in
    nightly) update_nightly ;;
    git) update_git ;;
    all)
      update_nightly
      update_git
      ;;
    *) error "usage: update.sh [nightly|git|all]" ;;
  esac
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
