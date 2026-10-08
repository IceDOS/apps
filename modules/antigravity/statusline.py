"""Antigravity CLI status line, laid out like climit's Claude Code one.

A title (dir, git, model, context) over a bordered table with one cell per quota window
(used%, burn rate, projected time to cap), then the resets, one per group of windows sharing one.
"""
import json
import math
import os
import re
import subprocess
import sys
import time
from pathlib import Path

# p10k theme colours (grey context/vcs, purple dir, cyan ahead/behind), plus orange for the model.
GREY, PURPLE, CYAN, ORANGE = "38;5;242", "38;2;145;65;172", "38;2;33;144;164", "38;2;217;119;87"

# nf-md-restore, nf-md-clock_alert_outline: time to window reset, projected time to cap.
RESET_GLYPH, ENDS_GLYPH = "\U000F099B ", "\U000F05CE "
DIR_GLYPH, BRANCH_GLYPH = "\U000F024B ", "\U000F02A2 "

# nf-md-network_strength_off / _1.._4, nf-md-lightning_bolt_circle; cool to hot as effort rises
EFFORT_GLYPHS = {
    "off": ("\U000F08FC", "2"),
    "low": ("\U000F08F4", "32"),
    "medium": ("\U000F08F6", "33"),
    "high": ("\U000F08F8", "38;5;208"),
    "xhigh": ("\U000F08FA", "31"),
    "max": ("\U000F0820", "31;1"),
}

FAMILY_SHORT = {"gemini": "gem", "3p": "3p"}
WINDOW_SHORT = {"5h": "5h", "seven_day": "wk", "weekly": "wk", "day": "day"}
WINDOW_RANK = {"5h": 0, "day": 0, "seven_day": 1, "weekly": 1}

SEP, RULE = " │ ", "─"
# rule junction by (separator above, separator below)
JOINTS = {(True, True): "┼", (True, False): "┴", (False, True): "┬", (False, False): RULE}
ANSI = re.compile(r"\x1b\[[0-9;]*m")

SETTINGS = Path.home() / ".gemini/antigravity-cli/settings.json"
HISTORY = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "antigravity-statusline/quota.json"

# Same tuning as climit: a full weekly window of samples plus a day of slack, a 60 min rate lookback.
HISTORY_MS = 8 * 86_400_000
LOOKBACK_MS = 60 * 60_000
# A window starts when its reset moves later by more than this; reset_in_seconds jitters every redraw.
RESET_SHIFT_MS = 10 * 60_000
# Without a reset on both samples, a drop this far below the window's peak marks a reset.
RESET_DROP = 5.0
# Resets this close count as the same one when grouping windows.
RESET_GROUP_MS = 60_000


def c(code, s):
    return s if os.environ.get("NO_COLOR") else f"\033[{code}m{s}\033[0m"


def width(s):
    return len(ANSI.sub("", s))


def util_code(u):
    return "32" if u < 50 else ("33" if u < 80 else "31")


def pie(pct):
    """nf-md-circle_slice_1..8 filled in 12.5% steps."""
    return chr(0xF0A9E + min(7, max(0, math.ceil(pct / 12.5) - 1)))


def fmt_dur(ms):
    s = max(0, int(ms // 1000))
    d, s = divmod(s, 86400)
    h, s = divmod(s, 3600)
    m, s = divmod(s, 60)
    if d:
        return f"{d}d{h}h"
    if h:
        return f"{h}h{m}m"
    if m:
        return f"{m}m"
    return f"{s}s"


# ---------- title ----------
def git_info(cwd):
    """(branch, dirty, behind, ahead) for cwd, or None outside a work tree."""
    try:
        proc = subprocess.run(
            ["git", "--no-optional-locks", "-C", cwd, "status", "--porcelain=v2", "--branch"],
            capture_output=True, text=True, timeout=1, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode:
        return None
    oid, branch, dirty, ahead, behind = "", "", False, 0, 0
    for line in proc.stdout.splitlines():
        if line.startswith("# branch.oid "):
            oid = line.split()[2]
        elif line.startswith("# branch.head "):
            branch = line.split(maxsplit=2)[2]
        elif line.startswith("# branch.ab "):
            a, b = line.split()[2:4]
            ahead, behind = int(a), -int(b)
        elif not line.startswith("#"):
            dirty = True
    if branch == "(detached)":
        branch = "@" + oid[:8]
    return branch, dirty, behind, ahead


def short_path(cwd, project):
    """cwd relative to the project dir (named by its basename), else ~-shortened."""
    project = (project or "").rstrip("/")
    home = str(Path.home())
    if project and (cwd == project or cwd.startswith(project + "/")):
        path = os.path.basename(project) + cwd[len(project) :]
    elif cwd == home or cwd.startswith(home + "/"):
        path = "~" + cwd[len(home) :]
    else:
        path = cwd
    parts = path.split("/")
    return path if len(parts) <= 3 else "/".join([parts[0], "…", *parts[-2:]])


def context_pct(payload):
    ctx = payload.get("context_window") or {}
    pct, size = ctx.get("used_percentage"), ctx.get("context_window_size")
    usage = ctx.get("current_usage") or {}
    if usage:
        used = sum(
            usage.get(k) or 0
            for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")
        )
        return 100.0 * used / size if isinstance(size, (int, float)) and size else None
    return float(pct) if isinstance(pct, (int, float)) else None


def model_label(payload):
    model = payload.get("model") or {}
    name = model.get("display_name") or model.get("id")
    if not name:
        return None
    effort = (model.get("effort") or "").lower()
    if effort in EFFORT_GLYPHS:
        # display names carry the level too ("Gemini 3.8 Flash (High)")
        name = re.sub(r"\s*\(" + re.escape(effort) + r"\)$", "", name, flags=re.IGNORECASE)
        glyph, code = EFFORT_GLYPHS[effort]
        return c(code, glyph) + " " + c(ORANGE, name)
    return c(ORANGE, name)


def render_title(payload):
    workspace = payload.get("workspace") or {}
    cwd = workspace.get("current_dir") or payload.get("cwd") or os.getcwd()
    where = c(PURPLE, DIR_GLYPH + short_path(cwd, workspace.get("project_dir")))
    if git := git_info(cwd):
        branch, dirty, behind, ahead = git
    else:
        vcs = payload.get("vcs") or {}
        branch, dirty, behind, ahead = vcs.get("branch"), vcs.get("dirty"), 0, 0
    if branch:
        arrows = ("⇣" if behind else "") + ("⇡" if ahead else "")
        where += " " + c(GREY, BRANCH_GLYPH + branch) + (c("33", "*") if dirty else "") \
            + (c(CYAN, arrows) if arrows else "")
    head = [where]
    if model := model_label(payload):
        head.append(model)
    if (ctx := context_pct(payload)) is not None:
        head.append(c(util_code(ctx), f"{pie(ctx)} {ctx:.0f}%"))
    return "  ".join(head)


# ---------- quota history and burn rate ----------
def quota_samples(payload, now_ms):
    """{window key: (label, rank, used%, reset unix ms)} from the payload's quota buckets."""
    out = {}
    for key, q in (payload.get("quota") or {}).items():
        if not isinstance(q, dict) or not isinstance(q.get("remaining_fraction"), (int, float)):
            continue
        family, _, window = key.rpartition("-")
        if not family:
            family, window = "", key
        label = " ".join(
            p for p in (FAMILY_SHORT.get(family, family), WINDOW_SHORT.get(window, window)) if p
        )
        reset = q.get("reset_in_seconds")
        used = max(0.0, min(100.0, (1 - q["remaining_fraction"]) * 100))
        reset_ts = now_ms + int(reset * 1000) if isinstance(reset, (int, float)) else None
        out[key] = (label, WINDOW_RANK.get(window, 2), used, reset_ts)
    return out


def load_history():
    try:
        data = json.loads(HISTORY.read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def save_history(history):
    """Atomic write; agy sessions redraw concurrently, so each uses its own temp file."""
    try:
        HISTORY.parent.mkdir(parents=True, exist_ok=True)
        tmp = HISTORY.with_name(f"{HISTORY.name}.{os.getpid()}.tmp")
        tmp.write_text(json.dumps(history, separators=(",", ":")))
        os.replace(tmp, HISTORY)
    except OSError:
        pass


def record(history, samples, now_ms):
    """Append each window's sample, skipping one that repeats the last, and prune old rows."""
    for key, (_, _, used, reset_ts) in samples.items():
        rows = history.setdefault(key, [])
        if rows:
            _, last_used, last_reset = rows[-1]
            if last_reset is None or reset_ts is None:
                same_reset = last_reset is reset_ts
            else:
                same_reset = abs(last_reset - reset_ts) <= RESET_SHIFT_MS
            if same_reset and abs(last_used - used) < 1e-6:
                continue
        rows.append([now_ms, used, reset_ts])
    for key in list(history):
        rows = [r for r in history[key] if isinstance(r, list) and len(r) == 3 and r[0] > now_ms - HISTORY_MS]
        if rows:
            history[key] = rows
        else:
            del history[key]


def window_rows(rows):
    """Rows of the current window, minus late reports from the previous one."""
    start, peak, reset = 0, rows[0][1], rows[0][2]
    stale = set()
    for i in range(1, len(rows)):
        util, r = rows[i][1], rows[i][2]
        if r is not None and reset is not None:
            if r < reset - RESET_SHIFT_MS:
                stale.add(i)  # a session redrawing the previous window's numbers
                continue
            new_window = r > reset + RESET_SHIFT_MS
        else:
            new_window = util < peak - RESET_DROP
        if new_window:
            start, peak, reset = i, util, r
        else:
            peak = max(peak, util)
            reset = reset if reset is not None else r
    return [row for i, row in enumerate(rows) if i >= start and i not in stale]


def burn(rows, now_ms):
    """(%/hour, runway ms or None) over the last hour, decaying as 1/t once usage stops rising.

    Port of climit's rates.compute: the running peak absorbs sources that round differently."""
    win = window_rows(rows)
    util_now = max(row[1] for row in win)
    first_peak = next(i for i, row in enumerate(win) if row[1] == util_now)
    t_prev = win[first_peak - 1][0] if first_peak else win[0][0]
    t_start = max(min(now_ms - LOOKBACK_MS, t_prev), win[0][0])
    util_start = max((row[1] for row in win if row[0] <= t_start), default=win[0][1])
    per_min = max((util_now - util_start) / max((now_ms - t_start) / 60_000, 1e-9), 0.0)
    runway = (100.0 - util_now) / per_min * 60_000 if per_min > 1e-6 else None
    return per_min * 60, runway


# ---------- quota table ----------
def segment(label, used, per_hour, runway_ms, reset_left, label_width):
    seg = [label.rjust(label_width), c(util_code(used) + ";1", f"{used:.0f}%")]
    if per_hour >= 0.05:
        seg.append(c("2", f"{per_hour:.1f}/h"))
    # only a cap that lands before the reset is worth a countdown; a red runway is the alert
    if runway_ms is not None and runway_ms >= 1000 and (reset_left is None or runway_ms < reset_left):
        seg.append(c("31", ENDS_GLYPH + fmt_dur(runway_ms)))
    return " ".join(seg)


def table(rows):
    """Bordered table with a rule between rows; a cell is a str, or (str, span) covering `span` columns."""
    rows = [[x if isinstance(x, tuple) else (x, 1) for x in row] for row in rows]
    ncols = max(sum(span for _, span in row) for row in rows)
    rows = [row + [("", ncols - n)] if (n := sum(span for _, span in row)) < ncols else row for row in rows]
    widths = [0] * ncols
    for row in rows:
        col = 0
        for text, span in row:
            if span == 1:
                widths[col] = max(widths[col], width(text))
            col += span
    for row in rows:
        col = 0
        for text, span in row:
            need = width(text) - (sum(widths[col : col + span]) + 3 * (span - 1))
            for k in range(span):
                widths[col + k] += max(0, need // span + (k < need % span))
            col += span

    def rule(left, right, above, below):
        segs = [RULE * (w + 2) for w in widths]
        return c("2", left + "".join(seg + JOINTS[(k in above, k in below)]
                                     for k, seg in enumerate(segs, 1))[:-1] + right)

    lines, prev = [], set()
    for row in rows:
        col, cells, joints = 0, [], set()
        for text, span in row:
            w = sum(widths[col : col + span]) + 3 * (span - 1)
            cells.append(" " + text + " " * (w - width(text)) + " ")
            col += span
            joints.add(col)
        joints.discard(ncols)
        lines.append(rule("┌", "┐", prev, joints) if not lines else rule("├", "┤", prev, joints))
        bar = c("2", "│")
        lines.append(bar + bar.join(cells) + bar)
        prev = joints
    lines.append(rule("└", "┘", prev, set()))
    return "\n".join(lines)


def render_quota(payload, history, now_ms):
    samples = quota_samples(payload, now_ms)
    active = []
    for key, (label, rank, used, reset_ts) in samples.items():
        # 0% windows are hidden, as in climit
        if not round(used):
            continue
        per_hour, runway = burn(history[key], now_ms) if history.get(key) else (0.0, None)
        left = reset_ts - now_ms if reset_ts is not None else None
        active.append(((rank, not key.startswith("gemini-"), label), label, used, per_hour, runway, left))
    if not active:
        return None
    active.sort(key=lambda w: w[0])
    label_width = max(len(w[1]) for w in active)

    groups = []
    for w in active:
        left = w[5]
        if left is not None and groups and groups[-1][0] is not None and abs(left - groups[-1][0]) <= RESET_GROUP_MS:
            groups[-1][1].append(w)
        else:
            groups.append((left, [w]))
    usage, resets = [], []
    for left, ws in groups:
        usage += [segment(label, used, ph, rw, lf, label_width) for _, label, used, ph, rw, lf in ws]
        resets.append((c("2", RESET_GLYPH + fmt_dur(left)) if left is not None else "", len(ws)))
    rows = [usage]
    if any(text for text, _ in resets):
        rows.append(resets)
    return table(rows)


def render(payload, now_ms=None):
    now_ms = int(time.time() * 1000) if now_ms is None else now_ms
    history = load_history()
    if samples := quota_samples(payload, now_ms):
        record(history, samples, now_ms)
        save_history(history)
    quota = render_quota(payload, history, now_ms)
    return render_title(payload) + ("\n" + quota if quota else "")


def read_payload():
    if sys.stdin.isatty():
        return {}
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return {}
    return data if isinstance(data, dict) else {}


def setup(action, command, stack):
    """Merge/remove the statusLine block in agy's own settings file (it writes that file)."""
    data = None
    if SETTINGS.exists():
        try:
            data = json.loads(SETTINGS.read_text())
        except (OSError, ValueError):
            print(f"antigravity statusline: {SETTINGS} is not valid JSON; left untouched", file=sys.stderr)
            return 0
        if not isinstance(data, dict):
            data = None
    if action == "off":
        if data is None or "statusLine" not in data:
            return 0
        del data["statusLine"]
    else:
        desired = {"type": "command", "command": command}
        if stack:
            desired["stack_with_default"] = True
        # agy owns this file; skip the rewrite when only the mtime would change.
        if data is not None and data.get("statusLine") == desired:
            return 0
        data = {} if data is None else data
        data["statusLine"] = desired
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    tmp = SETTINGS.with_name(SETTINGS.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(tmp, SETTINGS)
    return 0


def main(argv):
    if argv and argv[0] == "--setup":
        stack = "--stack" in argv
        args = [a for a in argv[1:] if a != "--stack"]
        action = args[0] if args else "on"
        command = args[1] if len(args) > 1 else str(SETTINGS.parent / "statusline.sh")
        return setup(action, command, stack)
    print(render(read_payload()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
