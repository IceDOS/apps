#!/usr/bin/env python3
"""zed-agent-bridge: resume the agent session that belongs to a Zed agent-panel terminal thread."""

import argparse
import json
import os
import re
import secrets
import select
import shlex
import shutil
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
TMUX_SOCKET = "zed-agent-bridge"
_warned_dirs: set[Path] = set()


def state_dir() -> Path:
    base = Path(os.environ.get("XDG_STATE_HOME") or (Path.home() / ".local/state"))
    new_dir = base / "icedos" / "zed-agent-bridge"
    legacy_dir = base / "zed-agent-bridge"  # legacy path pre-2026-11
    if not new_dir.exists() and legacy_dir.exists():
        new_dir.parent.mkdir(parents=True, exist_ok=True)
        try:
            legacy_dir.rename(new_dir)
        except OSError:
            pass
    elif new_dir.exists() and legacy_dir.exists():
        for f in legacy_dir.iterdir():
            if not f.is_file():
                continue
            target = new_dir / f.name
            try:
                if not target.exists() or f.stat().st_mtime > target.stat().st_mtime:
                    f.replace(target)
                else:
                    f.unlink()
            except OSError:
                pass
        try:
            legacy_dir.rmdir()
        except OSError:
            pass
    return new_dir


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


def _pi_dir() -> Path:
    return Path.home() / ".config/pi-agent/sessions"


def pi_exists(sid: str) -> bool:
    return any(_pi_dir().glob(f"*/*_{sid}.jsonl"))


def pi_latest(cwd: str, since: float) -> str | None:
    best = None
    for path in _pi_dir().glob("*/*.jsonl"):
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
    # The antigravity launcher keeps agy's .gemini in the XDG data dir, not ~.
    base = Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local/share"))
    return base / "gemini/antigravity-cli/conversation_summaries.db"


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


def _agy_presence() -> Path:
    return _agy_db().parent / "presence"


def agy_held(sid: str) -> bool:
    """A live agy holds a flock on its conversation's presence file."""
    try:
        ino = (_agy_presence() / f"{sid}.lock").stat().st_ino
        locks = Path("/proc/locks").read_text()
    except OSError:
        return False
    return any(line.split()[5].endswith(f":{ino}") for line in locks.splitlines() if len(line.split()) > 5)


def agy_exists(sid: str) -> bool:
    # Resuming a conversation another agy holds would open that thread's session here.
    return bool(_agy_query("select 1 from conversation_summaries where conversation_id=?", (sid,))) and not agy_held(sid)


def _children() -> dict[int, list[int]]:
    kids: dict[int, list[int]] = {}
    for d in Path("/proc").iterdir():
        if not d.name.isdigit():
            continue
        try:
            ppid = int((d / "stat").read_text().rpartition(")")[2].split()[1])
        except (OSError, ValueError, IndexError):
            continue
        kids.setdefault(ppid, []).append(int(d.name))
    return kids


def agy_owned(root: int) -> str | None:
    """Conversation of the shallowest agy under root, read from the presence lock it holds open."""
    kids, level = _children(), [root]
    while level:
        for pid in level:
            try:
                if Path(f"/proc/{pid}/comm").read_text().strip() != "agy":
                    continue
                fds = list(Path(f"/proc/{pid}/fd").iterdir())
            except OSError:
                continue
            for fd in fds:
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                m = re.search(r"/antigravity-cli/presence/([^/]+)\.lock$", target)
                if m:
                    return m[1]
        # Breadth-first, so rlm's child agy processes never win over the thread's own agy.
        level = [k for pid in level for k in kids.get(pid, [])]
    return None


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


def _opencode_db() -> Path:
    base = Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local/share"))
    return base / "opencode/opencode.db"


def _opencode_query(sql: str, params=()) -> list:
    if not _opencode_db().exists():
        return []
    con = sqlite3.connect(f"file:{_opencode_db()}?mode=ro", uri=True, timeout=1)
    try:
        return con.execute(sql, params).fetchall()
    finally:
        con.close()


def opencode_exists(sid: str) -> bool:
    return bool(_opencode_query("select 1 from session_v2 where id=?", (sid,)))


def opencode_latest(cwd: str, since: float) -> str | None:
    rows = _opencode_query(
        "select id, directory, parent_id, time_created, time_updated from session_v2"
        " where parent_id is null order by coalesce(time_updated, time_created) desc limit 50"
    )
    target = cwd.rstrip("/") or "/"
    since_ms = since * 1000 if since < 1e11 else since
    for sid, directory, _pid, t_created, t_updated in rows:
        if ((directory or "").rstrip("/") or "/") == target:
            if max(t_updated or 0, t_created or 0) >= since_ms:
                return sid
    return None


LOCATORS = {
    "claude": {"exists": claude_exists, "latest": None},
    "pi-agent": {"exists": pi_exists, "latest": pi_latest},
    "antigravity": {"exists": agy_exists, "latest": agy_latest},
    "opencode": {"exists": opencode_exists, "latest": opencode_latest},
}


# Locators that can read the session from the launched process instead of guessing by cwd and time.
OWNED = {agy_latest: agy_owned}


def watch_once(tid, agent, latest, cwd, since, current, exact=False):
    sid = latest(cwd, since)
    # An exact answer wins over another thread's claim, which came from a guess.
    if sid and sid != current and (exact or not claimed_by_other(sid, tid)):
        write_state(tid, agent, sid)
        log(f"{tid}: {agent} session {sid}")
        return sid
    return current


def agent_launch_choice() -> tuple[str | None, list[str] | None, dict]:
    proc = subprocess.run(["agent-launch", "--print"], text=True, stdout=subprocess.PIPE, check=False)
    if proc.returncode != 0:
        return None, None, {}
    choice = json.loads(proc.stdout)
    # env carries the picked account (AI_ACCOUNT_<AGENT>); without it ai-account auto-picks
    return choice["agent"], choice["argv"], choice.get("env", {})


def plan_launch(cfg, state, locators, picker=agent_launch_choice):
    agents = cfg.get("agents", {})
    if state and state.get("agent") in agents:
        agent = agents[state["agent"]]
        locator = locators.get(agent.get("locator"))
        sid = state.get("session_id")
        if sid and locator and locator["exists"](sid):
            resume = [arg.replace("{id}", sid) for arg in agent.get("resumeArgs", [])]
            return state["agent"], list(agent.get("command", [])) + resume, sid, {}
    name, argv, env = picker()
    return name, argv, None, env


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
    owned = OWNED.get(latest)
    if owned:
        latest = lambda _cwd, _since: owned(parent)  # noqa: E731
    while True:
        alive = os.getppid() == parent
        try:
            current = watch_once(tid, agent, latest, cwd, since, current, exact=bool(owned))
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


def write_env(tid: str, env: dict[str, str]) -> Path:
    state_dir().mkdir(parents=True, exist_ok=True)
    tmp = state_dir() / f"{tid}.env.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with open(fd, "w", encoding="utf-8") as f:
            json.dump(env, f)
        target = state_dir() / f"{tid}.env"
        tmp.replace(target)
        return target
    except Exception:
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass
        raise


def tmux_session_name(tid: str) -> str:
    return f"zab-{re.sub(r'[:.]', '-', tid)}"


def detached_timeout_seconds(cfg: dict) -> float:
    return float(cfg.get("tmux", {}).get("detachedTimeout", 0)) * 60


def tmux_hook_command(timeout_secs: float, socket: str = TMUX_SOCKET) -> str:
    sock = shlex.quote(socket)
    delay = shlex.quote(str(timeout_secs))
    return f"run-shell -b 'zed-agent-bridge timeout-kill --socket {sock} --session #{{q:session_name}} --delay {delay}'"


def cmd_timeout_kill(socket: str, session: str, delay: float) -> int:
    token = secrets.token_hex(8)
    subprocess.run(
        ["tmux", "-L", socket, "-f", "/dev/null", "set-option", "-t", session, "@zab_detach_token", token],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(delay)
    res = subprocess.run(
        ["tmux", "-L", socket, "-f", "/dev/null", "display-message", "-t", session, "-p", "#{@zab_detach_token}:#{session_attached}"],
        capture_output=True,
        text=True,
    )
    if res.returncode != 0:
        return 0
    if res.stdout.strip() == f"{token}:0":
        subprocess.run(
            ["tmux", "-L", socket, "-f", "/dev/null", "kill-session", "-t", session],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    return 0


def tmux_has_session(session: str, socket: str = TMUX_SOCKET) -> bool:
    res = subprocess.run(
        ["tmux", "-L", socket, "-f", "/dev/null", "has-session", "-t", session],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return res.returncode == 0


def tmux_attach(session: str, socket: str = TMUX_SOCKET) -> None:
    os.execvp("tmux", ["tmux", "-L", socket, "-f", "/dev/null", "attach", "-t", session])


def tmux_create_session(
    session: str,
    inner_cmd: list[str],
    hook_cmd: str | None = None,
    socket: str = TMUX_SOCKET,
    title: str | None = None,
) -> None:
    cmd = [
        "tmux",
        "-L",
        socket,
        "-f",
        "/dev/null",
        "new-session",
        "-d",
        "-s",
        session,
        "-c",
        os.getcwd(),
        *inner_cmd,
    ]
    subprocess.run(cmd, check=True)
    subprocess.run(["tmux", "-L", socket, "-f", "/dev/null", "set-option", "-s", "escape-time", "0"], check=False)
    # Zed's keymap sends Shift+Enter as CSI 13;2u; without this tmux forwards a plain Enter.
    subprocess.run(["tmux", "-L", socket, "-f", "/dev/null", "set-option", "-s", "extended-keys", "on"], check=False)
    subprocess.run(["tmux", "-L", socket, "-f", "/dev/null", "set-option", "-t", session, "status", "off"], check=False)
    subprocess.run(["tmux", "-L", socket, "-f", "/dev/null", "set-option", "-t", session, "mouse", "on"], check=False)
    subprocess.run(["tmux", "-L", socket, "-f", "/dev/null", "set-option", "-t", session, "history-limit", "50000"], check=False)
    # Forward the agent's OSC title to Zed, which names the thread after it.
    subprocess.run(["tmux", "-L", socket, "-f", "/dev/null", "set-option", "-t", session, "set-titles", "on"], check=False)
    subprocess.run(["tmux", "-L", socket, "-f", "/dev/null", "set-option", "-t", session, "set-titles-string", "#T"], check=False)
    if title:
        # Seeds the title tmux sends on attach; otherwise it is the hostname.
        subprocess.run(["tmux", "-L", socket, "-f", "/dev/null", "select-pane", "-t", session, "-T", title], check=False)
    if hook_cmd:
        subprocess.run(["tmux", "-L", socket, "-f", "/dev/null", "set-hook", "-t", session, "client-detached", hook_cmd], check=False)


def build_inner_cmd(
    cfg_path: str,
    tid: str,
    agent: str,
    locator: str | None,
    since: float,
    sid: str | None,
    argv: list[str],
    env_file: str | None = None,
) -> list[str]:
    cmd = [
        sys.executable,
        os.path.abspath(__file__),
        "--config",
        cfg_path,
        "inner-launch",
        "--tid",
        tid,
        "--agent",
        agent,
        "--since",
        str(since),
    ]
    if locator:
        cmd.extend(["--locator", locator])
    if sid:
        cmd.extend(["--sid", sid])
    if env_file:
        cmd.extend(["--env-file", env_file])
    cmd.append("--")
    cmd.extend(argv)
    return cmd


def cmd_inner_launch(
    tid: str,
    agent: str,
    locator: str | None,
    since: float,
    sid: str | None,
    cmd_argv: list[str],
    env_file: str | None = None,
) -> int:
    if not cmd_argv:
        return 0
    saved_env = None
    if env_file:
        p = Path(env_file)
        try:
            saved_env = json.loads(p.read_text())
        except (OSError, ValueError) as e:
            log(f"inner-launch failed to read env-file {env_file}: {e!r}")
        finally:
            try:
                p.unlink(missing_ok=True)
            except OSError:
                pass
    else:
        log("inner-launch missing --env-file")
    # Keep tmux's TERM_PROGRAM: with Zed's, Claude Code skips extended keys and Shift+Enter submits.
    pane_keys = ("TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TMUX", "TMUX_PANE")
    pane_env = {k: os.environ[k] for k in pane_keys if k in os.environ}
    if saved_env:
        os.environ.clear()
        os.environ.update(saved_env)
        os.environ.update(pane_env)
    os.environ[ENV_PID] = str(os.getpid())
    os.environ[ENV_ID] = tid
    os.environ[ENV_AGENT] = agent
    latest = LOCATORS.get(locator, {}).get("latest") if locator else None
    if latest:
        _spawn_watcher(tid, agent, latest, os.getcwd(), since, sid)
    os.execvpe(cmd_argv[0], cmd_argv, os.environ)


def cmd_launch(cfg: dict, cfg_path: str) -> int:
    since = time.time() - 1
    resolved = None
    try:
        resolved = _resolve(cfg)
        if resolved and resolved[1]:
            emit_tty_title(resolved[1])
    except Exception as e:  # noqa: BLE001 - never block the agent
        log(f"resolve failed: {e!r}")
    tid = resolved[0] if resolved else None

    tmux_cfg = cfg.get("tmux", {})
    use_tmux = bool(tid and tmux_cfg.get("enable") and shutil.which("tmux"))

    if use_tmux:
        session = tmux_session_name(tid)
        try:
            if tmux_has_session(session):
                log(f"attach tid={tid} session={session}")
                tmux_attach(session)
                return 0
        except OSError as e:
            log(f"tmux attach failed, falling back to direct exec: {e!r}")
            use_tmux = False

    try:
        name, argv, sid, picked_env = plan_launch(cfg, read_state(tid) if tid else None, LOCATORS)
    except (OSError, ValueError, KeyError) as e:
        log(f"agent-launch failed: {e!r}")
        return 1
    if not name or not argv:
        return 0
    log(f"launch tid={tid} agent={name} resume={sid}")

    env = dict(os.environ)
    env.update(picked_env)
    if tid:
        env[ENV_ID] = tid
        env[ENV_AGENT] = name

    if use_tmux:
        tmux_env = dict(env)
        for drop in ("TERM", "TMUX", "TMUX_PANE"):
            tmux_env.pop(drop, None)
        # Claude Code drops to 256 colours inside tmux unless told the outer terminal does RGB.
        tmux_env.setdefault("CLAUDE_CODE_TMUX_TRUECOLOR", "1")
        timeout_secs = detached_timeout_seconds(cfg)
        hook_cmd = tmux_hook_command(timeout_secs) if timeout_secs > 0 else None
        session = tmux_session_name(tid)
        locator = cfg.get("agents", {}).get(name, {}).get("locator", "")
        env_file = str(state_dir() / f"{tid}.env")
        inner_cmd = build_inner_cmd(cfg_path, tid, name, locator, since, sid, argv, env_file=env_file)
        try:
            write_env(tid, tmux_env)
            tmux_create_session(session, inner_cmd, hook_cmd, title=resolved[1] if resolved else None)
            tmux_attach(session)
            return 0
        except Exception as e:
            if tmux_has_session(session):
                log(f"session {session} exists after creation failure, attaching: {e!r}")
                try:
                    tmux_attach(session)
                    return 0
                except OSError as ae:
                    log(f"tmux attach failed: {ae!r}")
            try:
                Path(env_file).unlink(missing_ok=True)
            except OSError:
                pass
            log(f"tmux new-session failed, falling back to direct exec: {e!r}")

    if tid:
        env[ENV_PID] = str(os.getpid())
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
    parser.add_argument("--config", default="")
    sub = parser.add_subparsers(dest="cmd", required=True)
    resolve = sub.add_parser("resolve")
    resolve.add_argument("--timeout", type=float, default=3.0)
    sub.add_parser("launch")
    sub.add_parser("claude-hook")
    inner = sub.add_parser("inner-launch")
    inner.add_argument("--tid", required=True)
    inner.add_argument("--agent", required=True)
    inner.add_argument("--locator", default=None)
    inner.add_argument("--since", type=float, default=0.0)
    inner.add_argument("--sid", default=None)
    inner.add_argument("--env-file", default=None)
    inner.add_argument("cmd_argv", nargs=argparse.REMAINDER)
    tk = sub.add_parser("timeout-kill")
    tk.add_argument("--socket", required=True)
    tk.add_argument("--session", required=True)
    tk.add_argument("--delay", type=float, required=True)
    args = parser.parse_args(argv)
    if args.cmd == "claude-hook":
        return claude_hook(sys.stdin)
    if args.cmd == "timeout-kill":
        return cmd_timeout_kill(args.socket, args.session, args.delay)
    if args.cmd == "inner-launch":
        cmd_argv = args.cmd_argv
        if cmd_argv and cmd_argv[0] == "--":
            cmd_argv = cmd_argv[1:]
        return cmd_inner_launch(args.tid, args.agent, args.locator, args.since, args.sid, cmd_argv, env_file=args.env_file)
    if not args.config:
        parser.error("--config is required for resolve and launch")
    cfg = json.loads(Path(args.config).read_text())
    if args.cmd == "resolve":
        return cmd_resolve(cfg, args.timeout)
    return cmd_launch(cfg, args.config)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
