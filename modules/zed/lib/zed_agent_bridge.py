#!/usr/bin/env python3
"""zed-agent-bridge: resume the agent session that belongs to a Zed agent-panel terminal thread."""

import argparse
import json
import os
import re
import secrets
import select
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote

ENV_ID = "ZED_AGENT_BRIDGE_ID"
ENV_AGENT = "ZED_AGENT_BRIDGE_AGENT"
ENV_PID = "ZED_AGENT_BRIDGE_PID"
NONCE_PREFIX = "zab-"


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state")
    return Path(base) / "zed-agent-bridge"


def log(msg: str) -> None:
    try:
        state_dir().mkdir(parents=True, exist_ok=True)
        with (state_dir() / "bridge.log").open("a") as f:
            f.write(f"{time.strftime('%F %T')} [{os.getpid()}] {msg}\n")
    except OSError:
        pass


def read_state(tid: str) -> dict | None:
    try:
        return json.loads((state_dir() / f"{tid}.json").read_text())
    except (OSError, ValueError):
        return None


def write_state(tid: str, agent: str, session_id: str) -> None:
    state_dir().mkdir(parents=True, exist_ok=True)
    tmp = state_dir() / f"{tid}.json.tmp"
    tmp.write_text(json.dumps({"agent": agent, "session_id": session_id}))
    tmp.replace(state_dir() / f"{tid}.json")


def claimed_by_other(session_id: str, tid: str) -> bool:
    for path in state_dir().glob("*.json"):
        if path.stem == tid:
            continue
        try:
            if json.loads(path.read_text()).get("session_id") == session_id:
                return True
        except (OSError, ValueError):
            continue
    return False


def _zed_titles(db: str) -> dict[str, str]:
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=1)
    try:
        return dict(con.execute("select terminal_id, title from sidebar_terminal_threads"))
    finally:
        con.close()


def resolve_local(db, emit_title, timeout):
    before = _zed_titles(db)
    nonce = NONCE_PREFIX + secrets.token_hex(6)
    emit_title(nonce)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for tid, title in _zed_titles(db).items():
            if title == nonce:
                return tid, before.get(tid)
        time.sleep(0.1)
    return None


def _read_line(fd: int, deadline: float) -> str | None:
    # Byte-wise so select() never misses a line already sitting in a userspace buffer.
    buf = b""
    while not buf.endswith(b"\n"):
        left = deadline - time.monotonic()
        if left <= 0 or not select.select([fd], [], [], left)[0]:
            return None
        chunk = os.read(fd, 1)
        if not chunk:
            return None
        buf += chunk
    return buf.decode().strip()


def resolve_remote(argv, emit_title, timeout):
    proc = subprocess.Popen(
        argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )
    try:
        deadline = time.monotonic() + timeout
        nonce = _read_line(proc.stdout.fileno(), deadline)
        if not nonce or not nonce.startswith(NONCE_PREFIX):
            return None
        emit_title(nonce)
        line = _read_line(proc.stdout.fileno(), deadline)
        result = json.loads(line) if line else None
        return (result["terminal_id"], result["previous_title"]) if result else None
    finally:
        proc.kill()
        proc.wait()


def ssh_argv(target: str, timeout: float) -> list[str]:
    return [
        "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=3", target,
        "zed-agent-bridge", "resolve", "--timeout", str(timeout),
    ]


def remote_target(cfg: dict) -> str | None:
    conn = os.environ.get("SSH_CONNECTION")
    if not conn or not cfg.get("remoteLookup", True):
        return None
    if cfg.get("sshTarget"):
        return cfg["sshTarget"]
    return f"{os.environ.get('USER', '')}@{conn.split()[0]}"


def emit_tty_title(title: str) -> None:
    with open("/dev/tty", "w") as tty:
        tty.write(f"\033]0;{title}\007")
        tty.flush()


def claude_exists(sid: str) -> bool:
    return any(Path.home().glob(f".claude/projects/*/{sid}.jsonl"))


def _prime_dir() -> Path:
    return Path.home() / ".config/prime-agent/sessions"


def prime_exists(sid: str) -> bool:
    return (_prime_dir() / f"{sid}.jsonl").exists()


def prime_latest(cwd: str, since: float) -> str | None:
    best = None
    for path in _prime_dir().glob("*.jsonl"):
        try:
            mtime = path.stat().st_mtime
            if mtime < since or (best and mtime <= best[0]):
                continue
            with path.open() as f:
                header = json.loads(f.readline())
        except (OSError, ValueError):
            continue
        if header.get("cwd") == cwd:
            best = (mtime, header["id"])
    return best[1] if best else None


def _agy_db() -> Path:
    return Path.home() / ".gemini/antigravity-cli/conversation_summaries.db"


def _agy_query(sql: str, params=()) -> list:
    if not _agy_db().exists():
        return []
    con = sqlite3.connect(f"file:{_agy_db()}?mode=ro", uri=True, timeout=1)
    try:
        return con.execute(sql, params).fetchall()
    finally:
        con.close()


def _parse_ts(value: str) -> float:
    s = value.replace("T", " ")
    base = datetime.strptime(s[:19], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    m = re.search(r"([+-])(\d\d):(\d\d)$", s)
    offset = 0 if not m else (int(m[2]) * 60 + int(m[3])) * (1 if m[1] == "+" else -1)
    return base.timestamp() - offset * 60


def _uri_paths(uris: str) -> set[str]:
    return {unquote(u[len("file://"):]).rstrip("/") for u in re.findall(r'file://[^\s",\]]+', uris)}


def agy_exists(sid: str) -> bool:
    return bool(_agy_query("select 1 from conversation_summaries where conversation_id=?", (sid,)))


def agy_latest(cwd: str, since: float) -> str | None:
    rows = _agy_query(
        "select conversation_id, workspace_uris, last_modified_time from conversation_summaries"
        " order by last_modified_time desc limit 50"
    )
    for cid, uris, ts in rows:
        try:
            if _parse_ts(str(ts)) >= since and cwd.rstrip("/") in _uri_paths(uris or ""):
                return cid
        except ValueError:
            continue
    return None


LOCATORS = {
    "claude": {"exists": claude_exists, "latest": None},
    "prime-agent": {"exists": prime_exists, "latest": prime_latest},
    "antigravity": {"exists": agy_exists, "latest": agy_latest},
}


def watch_once(tid, agent, latest, cwd, since, current):
    sid = latest(cwd, since)
    if sid and sid != current and not claimed_by_other(sid, tid):
        write_state(tid, agent, sid)
        log(f"{tid}: {agent} session {sid}")
        return sid
    return current


def pick_agent(cfg: dict) -> str | None:
    agents = cfg.get("agents", {})
    if not agents:
        return "claude"
    if len(agents) == 1:
        return next(iter(agents.keys()))
    if not sys.stdin.isatty():
        return cfg.get("defaultAgent") or "claude"

    labels = {}
    default_labels = {
        "prime-agent": "Prime Agent",
        "claude": "Claude Code",
        "antigravity": "Antigravity CLI",
    }
    for name, data in agents.items():
        lbl = data.get("label") or default_labels.get(name, name.replace("-", " ").title())
        labels[lbl] = name

    try:
        proc = subprocess.run(
            ["fzf", "--height=60%", "--layout=reverse", "--border", "--prompt=agent> "],
            input="\n".join(labels.keys()),
            text=True,
            stdout=subprocess.PIPE,
            check=False,
        )
        if proc.returncode == 0:
            choice = proc.stdout.strip()
            if choice in labels:
                return labels[choice]
        if proc.returncode in (1, 130):
            return None
    except FileNotFoundError:
        pass
    except Exception as e:  # noqa: BLE001
        log(f"picker error: {e!r}")
    return cfg.get("defaultAgent") or next(iter(agents.keys()))


def _clean_cmd(cmd: list[str]) -> list[str]:
    if len(cmd) > 1 and len(set(cmd)) == 1:
        return [cmd[0]]
    return cmd


def _clean_args(args: list[str]) -> list[str]:
    half = len(args) // 2
    if len(args) > 1 and len(args) % 2 == 0 and args[:half] == args[half:]:
        return args[:half]
    return args


def plan_launch(cfg, state, locators, picker=None):
    agents = cfg.get("agents", {})
    if state and state.get("agent") in agents:
        agent = agents[state["agent"]]
        locator = locators.get(agent.get("locator"))
        sid = state.get("session_id")
        if sid and locator and locator["exists"](sid):
            cmd = _clean_cmd(list(agent.get("command", [])))
            raw_args = _clean_args(list(agent.get("resumeArgs", [])))
            resume = [arg.replace("{id}", sid) for arg in raw_args]
            return state["agent"], cmd + resume, sid
    default = cfg.get("defaultAgent", "")
    if default and default not in ("", "agents", "selector") and default in agents:
        name = default
    else:
        name = (picker or pick_agent)(cfg)
    if name is None:
        return None, None, None
    if name in agents and agents[name].get("command"):
        return name, _clean_cmd(list(agents[name]["command"])), None
    return name, [name], None


def _has_ancestor(pid: int, depth: int = 6) -> bool:
    cur = os.getpid()
    for _ in range(depth):
        if cur == pid:
            return True
        try:
            stat = Path(f"/proc/{cur}/stat").read_text()
        except OSError:
            return False
        cur = int(stat.rpartition(")")[2].split()[1])
        if cur <= 1:
            return False
    return False


def claude_hook(stdin) -> int:
    try:
        tid = os.environ.get(ENV_ID)
        pid = os.environ.get(ENV_PID, "")
        if not tid or os.environ.get(ENV_AGENT) != "claude" or not pid.isdigit():
            return 0
        # A claude started by hand inside the thread inherits the env but isn't our process.
        if not _has_ancestor(int(pid)):
            return 0
        sid = json.load(stdin).get("session_id")
        if sid:
            write_state(tid, "claude", sid)
            log(f"{tid}: claude session {sid}")
    except Exception as e:  # noqa: BLE001 - a hook must never break Claude
        log(f"claude-hook failed: {e!r}")
    return 0


def _watch(tid, agent, latest, cwd, since, current, parent):
    while True:
        alive = os.getppid() == parent
        try:
            current = watch_once(tid, agent, latest, cwd, since, current)
        except Exception as e:  # noqa: BLE001
            log(f"watch failed: {e!r}")
        if not alive:
            return
        time.sleep(3)


def _spawn_watcher(tid, agent, latest, cwd, since, current):
    parent = os.getpid()
    if os.fork() != 0:
        return
    try:
        os.setsid()
        devnull = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 1, 2):
            os.dup2(devnull, fd)
        _watch(tid, agent, latest, cwd, since, current, parent)
    finally:
        os._exit(0)


def _resolve(cfg):
    timeout = float(cfg.get("resolveTimeout", 3))
    target = remote_target(cfg)
    if target:
        return resolve_remote(ssh_argv(target, timeout), emit_tty_title, timeout + 3)
    db = os.path.expanduser(cfg["zedDb"])
    if not os.path.exists(db):
        return None
    return resolve_local(db, emit_tty_title, timeout)


def cmd_launch(cfg: dict) -> int:
    since = time.time() - 1
    resolved = None
    try:
        resolved = _resolve(cfg)
        if resolved and resolved[1]:
            emit_tty_title(resolved[1])
    except Exception as e:  # noqa: BLE001 - never block the agent
        log(f"resolve failed: {e!r}")
    tid = resolved[0] if resolved else None
    name, argv, sid = plan_launch(cfg, read_state(tid) if tid else None, LOCATORS)
    if not name or not argv:
        return 0
    log(f"launch tid={tid} agent={name} resume={sid}")
    env = dict(os.environ)
    if tid:
        env.update({ENV_ID: tid, ENV_AGENT: name, ENV_PID: str(os.getpid())})
        locator = cfg.get("agents", {}).get(name, {}).get("locator", "")
        latest = LOCATORS.get(locator, {}).get("latest")
        if latest:
            _spawn_watcher(tid, name, latest, os.getcwd(), since, sid)
    os.execvpe(argv[0], argv, env)


def cmd_resolve(cfg: dict, timeout: float) -> int:
    def emit(nonce):
        sys.stdout.write(nonce + "\n")
        sys.stdout.flush()

    db = os.path.expanduser(cfg["zedDb"])
    result = resolve_local(db, emit, timeout)
    payload = {"terminal_id": result[0], "previous_title": result[1]} if result else None
    print(json.dumps(payload), flush=True)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="zed-agent-bridge")
    parser.add_argument("--config", required=True)
    sub = parser.add_subparsers(dest="cmd", required=True)
    resolve = sub.add_parser("resolve")
    resolve.add_argument("--timeout", type=float, default=3.0)
    sub.add_parser("launch")
    sub.add_parser("claude-hook")
    args = parser.parse_args(argv)
    if args.cmd == "claude-hook":
        return claude_hook(sys.stdin)
    cfg = json.loads(Path(args.config).read_text())
    if args.cmd == "resolve":
        return cmd_resolve(cfg, args.timeout)
    return cmd_launch(cfg)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
