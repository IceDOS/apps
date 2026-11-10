# Derivations for the headless session: setgid-`input` shim.
{
  pkgs,
  lib,
  sunshinePkg,
  steamVersion ? "0",
}:

let
  # Marker group for the input bridge; the wrapper alone turns it into `input` access.
  inputBridgeGroup = "sunshine-headless";

  # The input-bridge shim (lib/sunshine-headless-gid.c): gated exec of steam/gamescope/sunshine.
  gidExec = pkgs.runCommandCC "sunshine-headless-gid" { } ''
    $CC -O2 -Wall -DEXPECTED_GROUP='"${inputBridgeGroup}"' -DINPUT_GROUP='"input"' \
        ${./lib/sunshine-headless-gid.c} -o $out
    $CC -O2 -Wall -DTEST_MAIN -DEXPECTED_GROUP='"${inputBridgeGroup}"' -DINPUT_GROUP='"input"' \
        -DSTEAM_VERSION='"${steamVersion}"' -DGAMESCOPE_VERSION='"${pkgs.gamescope.version}"' \
        -DSUNSHINE_VERSION='"${sunshinePkg.version}"' \
        ${./lib/sunshine-headless-gid.c} -o $TMPDIR/sunshine-headless-gid-test
    ${lib.optionalString (pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform) ''
      $TMPDIR/sunshine-headless-gid-test
      $TMPDIR/sunshine-headless-gid-test ${pkgs.gamescope}/bin/gamescope
      $TMPDIR/sunshine-headless-gid-test ${sunshinePkg}/bin/sunshine
      $TMPDIR/sunshine-headless-gid-test "steam-${steamVersion}"
      $TMPDIR/sunshine-headless-gid-test "steam-${steamVersion}-bwrap"
      $TMPDIR/sunshine-headless-gid-test "sunshine-${sunshinePkg.version}"
    ''}
  '';
in
{
  inherit
    inputBridgeGroup
    gidExec
    ;
}
