#!/usr/bin/env python3
"""prime-add - copy the current Zed selection's LOCATION to the clipboard.

Reads ZED_RELATIVE_FILE, ZED_ROW and PRIME_ADD_SELECTED_TEXT from the env (Zed
exports task variables), copies "path:start[-end]" with no trailing newline so a
paste never submits, and leaves pasting to you. Multi-cursor is unsupported.

Manual-testing fallback:
    prime-add <ZED_FILE> <ZED_RELATIVE_FILE> <ZED_ROW> <ZED_SELECTED_TEXT>
"""

import os
import shutil
import signal
import subprocess
import sys

_SENSITIVE_ENV_PREFIXES = ("PRIME_ADD_", "ZED_")

# Full argv per tool: xclip defaults to PRIMARY, but ctrl-shift-v reads CLIPBOARD.
_CLIPBOARD_CMDS = (
    ["wl-copy"],
    ["xclip", "-selection", "clipboard"],
)

# The raw selection must never reach a long-lived process's /proc/<pid>/environ
# (wl-copy daemonizes).
_SAFE_ENV = {
    k: v
    for k, v in os.environ.items()
    if not k.startswith(_SENSITIVE_ENV_PREFIXES)
}


def _notify(message: str) -> None:
    """Surface a failure via notify-send (best effort; wrapper adds libnotify)."""
    try:
        subprocess.run(
            ["notify-send", "--urgency=critical", "prime-add", message],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=_SAFE_ENV,
            timeout=5,
        )
    except Exception:
        pass


def _kill(proc) -> None:
    """SIGKILL the child's whole process group and reap it."""
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except OSError:
        pass
    proc.wait()


def clipboard_copy(content: str) -> bool:
    """Copy to the clipboard; try wl-copy, then xclip.

    Children get their own process group: wl-copy forks a server child, and
    inherited pipes could wedge the caller.
    """
    for cmd in _CLIPBOARD_CMDS:
        if not shutil.which(cmd[0]):
            continue
        proc = None
        try:
            proc = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                env=_SAFE_ENV,
                start_new_session=True,
            )
            try:
                proc.stdin.write(content.encode())
                proc.stdin.close()
            except OSError:
                # tool exited before consuming stdin (no display, ...)
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    _kill(proc)
                continue
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                _kill(proc)
                continue  # timed out; fall through to the next tool
            if proc.returncode == 0:
                return True
        except OSError:
            if proc is not None and proc.poll() is None:
                _kill(proc)
            continue
    return False


def main(argv: list[str]) -> int:
    # Zed passes everything via env; 4 positional args are a testing fallback.
    if argv:
        if len(argv) != 4:
            print(
                "usage: prime-add <ZED_FILE> <ZED_RELATIVE_FILE> <ZED_ROW> <ZED_SELECTED_TEXT>",
                file=sys.stderr,
            )
            return 2
        file_path, rel_path, row_s, text = argv
    else:
        file_path = os.environ.get("ZED_FILE", "")
        rel_path = os.environ.get("ZED_RELATIVE_FILE") or file_path
        row_s = os.environ.get("ZED_ROW", "")
        text = os.environ.get(
            "PRIME_ADD_SELECTED_TEXT", os.environ.get("ZED_SELECTED_TEXT", "")
        )

    if not text:
        msg = "no selection to copy"
        _notify(msg)
        print(msg, file=sys.stderr)
        return 1

    if not rel_path:
        msg = "no file path (unsaved buffer or file outside the worktree?)"
        _notify(msg)
        print(msg, file=sys.stderr)
        return 1

    try:
        start = int(row_s)
    except ValueError:
        msg = f"bad ZED_ROW: {row_s!r}"
        _notify(msg)
        print(msg, file=sys.stderr)
        return 1
    if start < 1:
        msg = f"bad ZED_ROW: {row_s!r}"
        _notify(msg)
        print(msg, file=sys.stderr)
        return 1
    # End line = start + line breaks inside the selection; a trailing newline
    # terminates the last line rather than opening the next.
    nl = text.count("\n") - (1 if text.endswith("\n") else 0)
    end = start + max(nl, 0)
    location = f"{rel_path}:{start}" if end == start else f"{rel_path}:{start}-{end}"

    if not clipboard_copy(location):
        if any(shutil.which(cmd[0]) for cmd in _CLIPBOARD_CMDS):
            msg = "clipboard tool present but failed (is a display reachable?)"
        else:
            msg = "no clipboard tool found (wl-clipboard/xclip not on PATH)"
        _notify(msg)
        print(msg, file=sys.stderr)
        return 1
    print(f"copied {location}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
