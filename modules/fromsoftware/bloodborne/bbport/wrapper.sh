#!@shell@
# The AppImage's AppRun mounts its /nix over the host's, which hides host icon themes, fonts
# and the paths portals get. Overlay its store onto the host store instead.
exec 3< <(exec @appimage@ --appimage-mount)
mounter=$!
trap 'kill "$mounter" 2>/dev/null' EXIT
read -r mnt <&3 || exit 1

@bwrap@ --dev-bind / / --die-with-parent \
  --overlay-src /nix/store --overlay-src "$mnt/nix/store" --ro-overlay /nix/store \
  -- "$mnt/entrypoint" "$@" &
app=$!
# Backgrounded, so a signal reaches the trap at once instead of after the launcher exits.
trap 'kill "$app" 2>/dev/null' INT TERM HUP
wait "$app"
status=$?
while kill -0 "$app" 2>/dev/null; do
  wait "$app"
  status=$?
done
exit "$status"
