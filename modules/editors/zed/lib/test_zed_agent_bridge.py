#!/usr/bin/env python3
import json
import os
import sqlite3
import stat
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zed_agent_bridge as zab  # noqa: E402


class TmpHome(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        env = {
            "HOME": str(self.root),
            "XDG_STATE_HOME": str(self.root / "state"),
            "XDG_DATA_HOME": str(self.root / ".local/share"),
        }
        self._env = mock.patch.dict(os.environ, env)
        self._env.start()

    def tearDown(self):
        self._env.stop()
        self._tmp.cleanup()


class StateTest(TmpHome):
    def test_roundtrip(self):
        zab.write_state("t1", "claude", "s1")
        self.assertEqual(zab.read_state("t1"), {"agent": "claude", "session_id": "s1"})
        self.assertTrue((self.root / "state/icedos/zed-agent-bridge/t1.json").exists())

    def test_missing_state_is_none(self):
        self.assertIsNone(zab.read_state("nope"))

    def test_claimed_by_other(self):
        zab.write_state("t1", "pi-agent", "s1")
        self.assertTrue(zab.claimed_by_other("s1", "t2"))
        self.assertFalse(zab.claimed_by_other("s1", "t1"))
        self.assertFalse(zab.claimed_by_other("s2", "t2"))

    def test_migrates_legacy_state_dir(self):
        legacy = self.root / "state/zed-agent-bridge"
        legacy.mkdir(parents=True)
        (legacy / "t0.json").write_text('{"agent": "claude", "session_id": "s0"}')
        self.assertEqual(zab.read_state("t0"), {"agent": "claude", "session_id": "s0"})
        new_dir = self.root / "state/icedos/zed-agent-bridge"
        self.assertTrue((new_dir / "t0.json").exists())
        self.assertFalse(legacy.exists())

    def test_both_dirs_exist_merges_and_removes_legacy(self):
        legacy = self.root / "state/zed-agent-bridge"
        new_dir = self.root / "state/icedos/zed-agent-bridge"
        legacy.mkdir(parents=True)
        new_dir.mkdir(parents=True)
        (legacy / "t_only.json").write_text('{"agent": "claude", "session_id": "s_only"}')
        (new_dir / "t_older.json").write_text('{"agent": "old", "session_id": "s_old"}')
        (legacy / "t_older.json").write_text('{"agent": "new", "session_id": "s_new"}')
        now = time.time()
        os.utime(new_dir / "t_older.json", (now - 100, now - 100))
        os.utime(legacy / "t_older.json", (now, now))
        (new_dir / "t_newer.json").write_text('{"agent": "keep", "session_id": "s_keep"}')
        (legacy / "t_newer.json").write_text('{"agent": "drop", "session_id": "s_drop"}')
        os.utime(new_dir / "t_newer.json", (now, now))
        os.utime(legacy / "t_newer.json", (now - 100, now - 100))

        zab.state_dir()
        self.assertEqual(zab.read_state("t_only"), {"agent": "claude", "session_id": "s_only"})
        self.assertEqual(zab.read_state("t_older"), {"agent": "new", "session_id": "s_new"})
        self.assertEqual(zab.read_state("t_newer"), {"agent": "keep", "session_id": "s_keep"})
        self.assertFalse(legacy.exists())


def make_zed_db(path, rows):
    con = sqlite3.connect(path)
    con.execute(
        "create table sidebar_terminal_threads (terminal_id text primary key, title text not null)"
    )
    con.executemany("insert into sidebar_terminal_threads values (?, ?)", rows)
    con.commit()
    con.close()


def zed_db_exec(path, sql, params):
    con = sqlite3.connect(path)
    con.execute(sql, params)
    con.commit()
    con.close()


class ResolveTest(TmpHome):
    def setUp(self):
        super().setUp()
        self.db = str(self.root / "db.sqlite")
        make_zed_db(self.db, [("a", "✳ old"), ("b", "other")])

    def test_existing_thread_returns_previous_title(self):
        emit = lambda n: zed_db_exec(
            self.db, "update sidebar_terminal_threads set title=? where terminal_id='a'", (n,)
        )
        self.assertEqual(zab.resolve_local(self.db, emit, timeout=2), ("a", "✳ old"))

    def test_new_thread_has_no_previous_title(self):
        emit = lambda n: zed_db_exec(
            self.db, "insert into sidebar_terminal_threads values ('c', ?)", (n,)
        )
        self.assertEqual(zab.resolve_local(self.db, emit, timeout=2), ("c", None))

    def test_timeout_returns_none(self):
        self.assertIsNone(zab.resolve_local(self.db, lambda n: None, timeout=0.3))

    def test_remote_protocol_end_to_end(self):
        cfg = self.root / "cfg.json"
        cfg.write_text(json.dumps({"zedDb": self.db}))
        argv = [sys.executable, zab.__file__, "--config", str(cfg), "resolve", "--timeout", "2"]
        emit = lambda n: zed_db_exec(
            self.db, "update sidebar_terminal_threads set title=? where terminal_id='b'", (n,)
        )
        self.assertEqual(zab.resolve_remote(argv, emit, timeout=5), ("b", "other"))

    def test_remote_target(self):
        with mock.patch.dict(os.environ, {"SSH_CONNECTION": "100.1.2.3 5555 100.9.9.9 22", "USER": "ice"}):
            self.assertEqual(zab.remote_target({"remoteLookup": True, "sshTarget": ""}), "ice@100.1.2.3")
            self.assertEqual(zab.remote_target({"remoteLookup": True, "sshTarget": "me@host"}), "me@host")
            self.assertIsNone(zab.remote_target({"remoteLookup": False, "sshTarget": ""}))
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertIsNone(zab.remote_target({"remoteLookup": True, "sshTarget": ""}))


class LocatorTest(TmpHome):
    def _pi(self, sid, cwd, mtime):
        d = self.root / ".config/pi-agent/sessions" / f"--{cwd.strip('/')}--"
        d.mkdir(parents=True, exist_ok=True)
        p = d / f"2026-11-09T09-46-46-589Z_{sid}.jsonl"
        p.write_text(json.dumps({"type": "session", "id": sid, "cwd": cwd}) + "\n")
        os.utime(p, (mtime, mtime))

    def test_claude_exists(self):
        d = self.root / ".claude/projects/-home-x"
        d.mkdir(parents=True)
        (d / "s1.jsonl").write_text("{}\n")
        self.assertTrue(zab.LOCATORS["claude"]["exists"]("s1"))
        self.assertFalse(zab.LOCATORS["claude"]["exists"]("s2"))

    def test_pi_latest_picks_newest_in_cwd_after_since(self):
        now = time.time()
        self._pi("old", "/p", now - 100)
        self._pi("new", "/p", now - 5)
        self._pi("newer-other-cwd", "/q", now)
        latest = zab.LOCATORS["pi-agent"]["latest"]
        self.assertEqual(latest("/p", now - 50), "new")
        self.assertIsNone(latest("/p", now + 10))
        self.assertTrue(zab.LOCATORS["pi-agent"]["exists"]("old"))

    def test_antigravity_latest(self):
        d = self.root / ".local/share/gemini/antigravity-cli"
        d.mkdir(parents=True)
        con = sqlite3.connect(d / "conversation_summaries.db")
        con.execute(
            "create table conversation_summaries (conversation_id text, workspace_uris text, last_modified_time datetime)"
        )
        fmt = lambda t: time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(t)) + ".123456789+00:00"
        now = time.time()
        con.executemany(
            "insert into conversation_summaries values (?, ?, ?)",
            [
                ("c-old", '["file:///p"]', fmt(now - 100)),
                ("c-new", '["file:///p"]', fmt(now - 5)),
                ("c-other", '["file:///q"]', fmt(now)),
            ],
        )
        con.commit()
        con.close()
        self.assertEqual(zab.LOCATORS["antigravity"]["latest"]("/p", now - 50), "c-new")
        self.assertTrue(zab.LOCATORS["antigravity"]["exists"]("c-old"))
        self.assertFalse(zab.LOCATORS["antigravity"]["exists"]("nope"))

    def test_opencode_latest(self):
        d = self.root / ".local/share/opencode"
        self.assertFalse(zab.LOCATORS["opencode"]["exists"]("none"))
        self.assertIsNone(zab.LOCATORS["opencode"]["latest"]("/p", time.time()))

        d.mkdir(parents=True)
        con = sqlite3.connect(d / "opencode.db")
        con.execute(
            """create table session_v2 (
              id text primary key,
              project_id text not null,
              workspace_id text,
              parent_id text,
              fork_session_id text,
              fork_boundary text,
              slug text not null,
              directory text not null,
              path text,
              title text,
              version text not null,
              share_url text,
              summary_additions integer,
              summary_deletions integer,
              summary_files integer,
              summary_diffs text,
              metadata text,
              cost real default 0 not null,
              tokens_input integer default 0 not null,
              tokens_output integer default 0 not null,
              tokens_reasoning integer default 0 not null,
              tokens_cache_read integer default 0 not null,
              tokens_cache_write integer default 0 not null,
              revert text,
              permission text,
              agent text,
              model text,
              time_created integer not null,
              time_updated integer not null,
              time_busy integer,
              time_idle integer,
              time_viewed integer,
              idle_outcome text,
              time_compacting integer,
              time_archived integer,
              time_suspended integer,
              resume_attempts integer default 0 not null
            )"""
        )
        now = time.time()
        now_ms = int(now * 1000)
        insert_sql = (
            "insert into session_v2 (id, project_id, slug, directory, version, parent_id, time_created, time_updated) "
            "values (?, 'p1', 'slug', ?, '1.0', ?, ?, ?)"
        )
        con.executemany(
            insert_sql,
            [
                ("s-old", "/p", None, now_ms - 100000, now_ms - 100000),
                ("s-new", "/p", None, now_ms - 5000, now_ms - 5000),
                ("s-child", "/p", "s-new", now_ms - 1000, now_ms - 1000),
                ("s-other", "/q", None, now_ms, now_ms),
            ],
        )
        con.commit()
        con.close()
        self.assertEqual(zab.LOCATORS["opencode"]["latest"]("/p", now - 50), "s-new")
        self.assertIsNone(zab.LOCATORS["opencode"]["latest"]("/p", now + 10))
        self.assertIsNone(zab.LOCATORS["opencode"]["latest"]("/other", now - 50))
        self.assertTrue(zab.LOCATORS["opencode"]["exists"]("s-old"))
        self.assertTrue(zab.LOCATORS["opencode"]["exists"]("s-child"))
        self.assertFalse(zab.LOCATORS["opencode"]["exists"]("nope"))

    def test_watch_once_records_unclaimed_session(self):
        zab.write_state("other", "pi-agent", "taken")
        latest = lambda cwd, since: "taken"
        self.assertIsNone(zab.watch_once("t1", "pi-agent", latest, "/p", 0, None))
        latest = lambda cwd, since: "mine"
        self.assertEqual(zab.watch_once("t1", "pi-agent", latest, "/p", 0, None), "mine")
        self.assertEqual(zab.read_state("t1")["session_id"], "mine")


CFG = {
    "agents": {
        "claude": {"command": ["claude"], "resumeArgs": ["--resume", "{id}"], "locator": "claude"},
        "pi-agent": {"command": ["pi-agent"], "resumeArgs": ["--resume", "{id}"], "locator": "pi-agent"},
    },
}
FAKE_LOCATORS = {
    "claude": {"exists": lambda s: s == "alive", "latest": None},
    "pi-agent": {"exists": lambda s: s == "alive", "latest": None},
}
PICK_CLAUDE = lambda: ("claude", ["claude"], {})


class LaunchTest(TmpHome):
    def test_no_state_asks_agent_launch(self):
        self.assertEqual(zab.plan_launch(CFG, None, FAKE_LOCATORS, PICK_CLAUDE), ("claude", ["claude"], None, {}))

    def test_state_resumes_recorded_agent_without_picker(self):
        state = {"agent": "pi-agent", "session_id": "alive"}
        picker = mock.Mock()
        self.assertEqual(
            zab.plan_launch(CFG, state, FAKE_LOCATORS, picker),
            ("pi-agent", ["pi-agent", "--resume", "alive"], "alive", {}),
        )
        picker.assert_not_called()

    def test_deleted_session_asks_agent_launch(self):
        state = {"agent": "pi-agent", "session_id": "gone"}
        self.assertEqual(zab.plan_launch(CFG, state, FAKE_LOCATORS, PICK_CLAUDE)[1], ["claude"])

    def test_unknown_agent_asks_agent_launch(self):
        state = {"agent": "removed", "session_id": "alive"}
        self.assertEqual(zab.plan_launch(CFG, state, FAKE_LOCATORS, PICK_CLAUDE)[1], ["claude"])

    def test_picker_cancelled_returns_none(self):
        self.assertEqual(zab.plan_launch(CFG, None, FAKE_LOCATORS, lambda: (None, None, {})), (None, None, None, {}))

    def test_agent_launch_choice_reads_print_output(self):
        env = {"AI_ACCOUNT_CLAUDE": "default"}
        out = mock.Mock(returncode=0, stdout=json.dumps({"agent": "claude", "argv": ["claude"], "env": env}))
        with mock.patch.object(zab.subprocess, "run", return_value=out) as run:
            self.assertEqual(zab.agent_launch_choice(), ("claude", ["claude"], env))
        self.assertEqual(run.call_args.args[0], ["agent-launch", "--print"])

    def test_agent_launch_choice_cancelled(self):
        with mock.patch.object(zab.subprocess, "run", return_value=mock.Mock(returncode=1, stdout="")):
            self.assertEqual(zab.agent_launch_choice(), (None, None, {}))


class HookTest(TmpHome):
    def _hook(self, env):
        import io
        with mock.patch.dict(os.environ, env):
            return zab.claude_hook(io.StringIO(json.dumps({"session_id": "s9"})))

    def test_hook_records_session_for_own_agent(self):
        self._hook({zab.ENV_ID: "t1", zab.ENV_AGENT: "claude", zab.ENV_PID: str(os.getpid())})
        self.assertEqual(zab.read_state("t1"), {"agent": "claude", "session_id": "s9"})

    def test_hook_ignores_unrelated_claude(self):
        self._hook({zab.ENV_ID: "t1", zab.ENV_AGENT: "claude", zab.ENV_PID: "999999999"})
        self.assertIsNone(zab.read_state("t1"))

    def test_hook_ignores_other_agent(self):
        self._hook({zab.ENV_ID: "t1", zab.ENV_AGENT: "pi-agent", zab.ENV_PID: str(os.getpid())})
        self.assertIsNone(zab.read_state("t1"))



class TmuxTest(TmpHome):
    def test_name_sanitizing(self):
        self.assertEqual(zab.tmux_session_name("t1"), "zab-t1")
        self.assertEqual(zab.tmux_session_name("thread:1.2.3:abc"), "zab-thread-1-2-3-abc")
        name = zab.tmux_session_name("colon:and.dot")
        self.assertNotIn(":", name)
        self.assertNotIn(".", name)
        self.assertTrue(name.startswith("zab-"))

    def test_hook_command(self):
        cmd = zab.tmux_hook_command(300.0, socket="zab-sock")
        self.assertEqual(
            cmd,
            "run-shell -b 'zed-agent-bridge timeout-kill --socket zab-sock --session #{q:session_name} --delay 300.0'"
        )
        cmd_quoted = zab.tmux_hook_command(300.0, socket="zab sock; evil")
        self.assertIn("--socket 'zab sock; evil'", cmd_quoted)
        self.assertIn("#{q:session_name}", cmd_quoted)

    def test_timeout_kill_matches_token_and_kills(self):
        with mock.patch.object(zab.time, "sleep"), \
             mock.patch.object(zab.subprocess, "run") as mock_run:
            mock_run.side_effect = [
                mock.Mock(returncode=0), # set-option
                mock.Mock(returncode=0, stdout="tok123:0"), # display-message
                mock.Mock(returncode=0), # kill-session
            ]
            with mock.patch.object(zab.secrets, "token_hex", return_value="tok123"):
                zab.cmd_timeout_kill("sock1", "s1", 10.0)
            self.assertEqual(mock_run.call_count, 3)
            kill_args = mock_run.call_args_list[2][0][0]
            self.assertIn("kill-session", kill_args)
            self.assertIn("s1", kill_args)

    def test_timeout_kill_mismatched_token_does_not_kill(self):
        with mock.patch.object(zab.time, "sleep"), \
             mock.patch.object(zab.subprocess, "run") as mock_run:
            mock_run.side_effect = [
                mock.Mock(returncode=0), # set-option
                mock.Mock(returncode=0, stdout="other_token:0"), # display-message (superseded)
            ]
            with mock.patch.object(zab.secrets, "token_hex", return_value="tok123"):
                zab.cmd_timeout_kill("sock1", "s1", 10.0)
            self.assertEqual(mock_run.call_count, 2)

    def test_detached_timeout_seconds(self):
        self.assertEqual(zab.detached_timeout_seconds({"tmux": {"detachedTimeout": 5}}), 300.0)
        self.assertEqual(zab.detached_timeout_seconds({"tmux": {"detachedTimeout": 0.05}}), 3.0)
        self.assertEqual(zab.detached_timeout_seconds({"tmux": {"detachedTimeout": 0}}), 0.0)
        self.assertEqual(zab.detached_timeout_seconds({}), 0.0)

    def test_tmux_disabled_path_unchanged(self):
        cfg = {"agents": {"claude": {"command": ["claude"]}}}
        with mock.patch.object(zab, "_resolve", return_value=("t1", "title")), \
             mock.patch.object(zab, "plan_launch", return_value=("claude", ["claude"], None, {})), \
             mock.patch.object(zab, "tmux_has_session") as mock_has, \
             mock.patch.object(zab.os, "execvpe") as mock_exec:
            zab.cmd_launch(cfg, "/dummy/cfg.json")
        mock_has.assert_not_called()
        mock_exec.assert_called_once()
        self.assertEqual(mock_exec.call_args[0][0], "claude")
        self.assertEqual(mock_exec.call_args[0][2][zab.ENV_ID], "t1")

    def test_tmux_enabled_without_tid_runs_execvpe(self):
        cfg = {"tmux": {"enable": True}, "agents": {"claude": {"command": ["claude"]}}}
        with mock.patch.object(zab, "_resolve", return_value=None), \
             mock.patch.object(zab, "plan_launch", return_value=("claude", ["claude"], None, {})), \
             mock.patch.object(zab, "tmux_has_session") as mock_has, \
             mock.patch.object(zab.os, "execvpe") as mock_exec:
            zab.cmd_launch(cfg, "/dummy/cfg.json")
        mock_has.assert_not_called()
        mock_exec.assert_called_once()

    def test_attach_decision_when_session_exists(self):
        cfg = {"tmux": {"enable": True}, "agents": {}}
        with mock.patch.object(zab.shutil, "which", return_value="/bin/tmux"), \
             mock.patch.object(zab, "_resolve", return_value=("t1", "title")), \
             mock.patch.object(zab, "tmux_has_session", return_value=True) as mock_has, \
             mock.patch.object(zab, "plan_launch") as mock_plan, \
             mock.patch.object(zab, "tmux_attach") as mock_attach:
            zab.cmd_launch(cfg, "/dummy/cfg.json")
        mock_has.assert_called_once_with("zab-t1")
        mock_plan.assert_not_called()
        mock_attach.assert_called_once_with("zab-t1")

    def test_write_env_mode_0600(self):
        p = zab.write_env("t1", {"FOO": "bar"})
        self.assertTrue(p.exists())
        self.assertEqual(stat.S_IMODE(p.stat().st_mode), 0o600)
        self.assertEqual(json.loads(p.read_text()), {"FOO": "bar"})

    def test_write_env_failure_unlinks_tmp(self):
        with mock.patch.object(zab.json, "dump", side_effect=ValueError("boom")):
            with self.assertRaises(ValueError):
                zab.write_env("t_fail", {"A": "B"})
        tmp_file = zab.state_dir() / "t_fail.env.tmp"
        self.assertFalse(tmp_file.exists())

    def test_tmux_create_session_no_e_args(self):
        with mock.patch.object(zab.subprocess, "run") as mock_run:
            zab.tmux_create_session("sess1", ["python3", "agent"], hook_cmd="hook-cmd", socket="sock1", title="✳ Old")
        new_sess_call = mock_run.call_args_list[0][0][0]
        self.assertIn("new-session", new_sess_call)
        self.assertNotIn("-e", new_sess_call)
        self.assertIn("-c", new_sess_call)
        self.assertIn("sess1", new_sess_call)
        self.assertEqual(new_sess_call[-2:], ["python3", "agent"])
        calls = [c[0][0] for c in mock_run.call_args_list]
        self.assertTrue(any("mouse" in c and "on" in c for c in calls))
        self.assertTrue(any("status" in c and "off" in c for c in calls))
        self.assertTrue(any("history-limit" in c and "50000" in c for c in calls))
        self.assertTrue(any("set-titles" in c and "on" in c for c in calls))
        self.assertIn(["tmux", "-L", "sock1", "-f", "/dev/null", "select-pane", "-t", "sess1", "-T", "✳ Old"], calls)

    def test_new_session_decision_and_env_forwarding(self):
        cfg = {"tmux": {"enable": True, "detachedTimeout": 0.05}, "agents": {}}
        outer_env = {"PATH": "/custom/bin", "TERM": "xterm-256color", "TMUX": "stale", "TMUX_PANE": "%0", "MY_VAR": "outer_val"}
        with mock.patch.dict(os.environ, outer_env, clear=True),              mock.patch.object(zab.shutil, "which", return_value="/bin/tmux"),              mock.patch.object(zab, "_resolve", return_value=("t1", "title")),              mock.patch.object(zab, "tmux_has_session", return_value=False),              mock.patch.object(zab, "plan_launch", return_value=("claude", ["claude"], None, {"AI_ACCOUNT": "default"})),              mock.patch.object(zab, "tmux_create_session") as mock_create,              mock.patch.object(zab, "tmux_attach") as mock_attach:
            zab.cmd_launch(cfg, "/dummy/cfg.json")
        mock_create.assert_called_once()
        args, kwargs = mock_create.call_args
        self.assertEqual(args[0], "zab-t1")
        inner_cmd = args[1]
        self.assertIn("inner-launch", inner_cmd)
        self.assertIn("--env-file", inner_cmd)
        env_file = Path(inner_cmd[inner_cmd.index("--env-file") + 1])
        self.assertTrue(env_file.exists())
        self.assertEqual(stat.S_IMODE(env_file.stat().st_mode), 0o600)
        saved = json.loads(env_file.read_text())
        self.assertEqual(saved["AI_ACCOUNT"], "default")
        self.assertEqual(saved[zab.ENV_ID], "t1")
        self.assertEqual(saved[zab.ENV_AGENT], "claude")
        self.assertEqual(saved["MY_VAR"], "outer_val")
        self.assertEqual(saved["PATH"], "/custom/bin")
        self.assertNotIn("TERM", saved)
        self.assertNotIn("TMUX", saved)
        self.assertNotIn("TMUX_PANE", saved)
        self.assertIsNotNone(args[2])
        mock_attach.assert_called_once_with("zab-t1")

    def test_fallback_when_tmux_missing(self):
        cfg = {"tmux": {"enable": True}, "agents": {"claude": {"command": ["claude"]}}}
        with mock.patch.object(zab.shutil, "which", return_value=None),              mock.patch.object(zab, "_resolve", return_value=("t1", "title")),              mock.patch.object(zab, "plan_launch", return_value=("claude", ["claude"], None, {})),              mock.patch.object(zab.os, "execvpe") as mock_exec:
            zab.cmd_launch(cfg, "/dummy/cfg.json")
        mock_exec.assert_called_once()

    def test_fallback_when_new_session_fails(self):
        cfg = {"tmux": {"enable": True}, "agents": {"claude": {"command": ["claude"]}}}
        with mock.patch.object(zab.shutil, "which", return_value="/bin/tmux"), \
             mock.patch.object(zab, "_resolve", return_value=("t1", "title")), \
             mock.patch.object(zab, "tmux_has_session", return_value=False), \
             mock.patch.object(zab, "plan_launch", return_value=("claude", ["claude"], None, {})), \
             mock.patch.object(zab, "tmux_create_session", side_effect=zab.subprocess.CalledProcessError(1, "tmux")), \
             mock.patch.object(zab.os, "execvpe") as mock_exec:
            zab.cmd_launch(cfg, "/dummy/cfg.json")
        mock_exec.assert_called_once()

    def test_attach_when_concurrent_session_created(self):
        cfg = {"tmux": {"enable": True}, "agents": {"claude": {"command": ["claude"]}}}
        with mock.patch.object(zab.shutil, "which", return_value="/bin/tmux"), \
             mock.patch.object(zab, "_resolve", return_value=("t1", "title")), \
             mock.patch.object(zab, "tmux_has_session", side_effect=[False, True]), \
             mock.patch.object(zab, "plan_launch", return_value=("claude", ["claude"], None, {})), \
             mock.patch.object(zab, "tmux_create_session", side_effect=zab.subprocess.CalledProcessError(1, "tmux")), \
             mock.patch.object(zab, "tmux_attach") as mock_attach, \
             mock.patch.object(zab.os, "execvpe") as mock_exec:
            res = zab.cmd_launch(cfg, "/dummy/cfg.json")
        self.assertEqual(res, 0)
        mock_attach.assert_called_once_with("zab-t1")
        mock_exec.assert_not_called()

    def test_inner_launch_loads_env_and_deletes_file(self):
        env_file = self.root / "t1.env"
        fd = os.open(env_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with open(fd, "w") as f:
            json.dump({"CUSTOM_KEY": "custom_val", "PATH": "/usr/bin", "TERM_PROGRAM": "zed"}, f)
        pane_env = {"TERM": "tmux-256color", "TMUX": "/tmp/sock,1,0", "TMUX_PANE": "%1", "TERM_PROGRAM": "tmux", "OLD": "drop"}
        with mock.patch.dict(os.environ, pane_env, clear=True), \
             mock.patch.object(zab.os, "execvpe") as mock_exec, \
             mock.patch.object(zab, "_spawn_watcher") as mock_watch:
            zab.cmd_inner_launch("t1", "pi-agent", "pi-agent", 100.0, "s1", ["pi-agent", "--resume", "s1"], env_file=str(env_file))
            self.assertFalse(env_file.exists())
            self.assertEqual(os.environ["CUSTOM_KEY"], "custom_val")
            self.assertEqual(os.environ["TERM"], "tmux-256color")
            self.assertEqual(os.environ["TMUX"], "/tmp/sock,1,0")
            self.assertEqual(os.environ["TMUX_PANE"], "%1")
            self.assertEqual(os.environ["TERM_PROGRAM"], "tmux")
            self.assertNotIn("OLD", os.environ)
            self.assertEqual(os.environ[zab.ENV_PID], str(os.getpid()))
            self.assertEqual(os.environ[zab.ENV_ID], "t1")
            self.assertEqual(os.environ[zab.ENV_AGENT], "pi-agent")
            mock_watch.assert_called_once()
            mock_exec.assert_called_once_with("pi-agent", ["pi-agent", "--resume", "s1"], mock.ANY)

    def test_main_timeout_kill_with_and_without_config(self):
        with mock.patch.object(zab, "cmd_timeout_kill", return_value=0) as mock_tk:
            zab.main(["timeout-kill", "--socket", "s1", "--session", "sess1", "--delay", "5.0"])
            mock_tk.assert_called_with("s1", "sess1", 5.0)

            mock_tk.reset_mock()
            zab.main(["--config", "/path/to/cfg.json", "timeout-kill", "--socket", "s2", "--session", "sess2", "--delay", "10.0"])
            mock_tk.assert_called_with("s2", "sess2", 10.0)

    def test_inner_launch_missing_env_file_keeps_env_and_execs(self):
        missing_file = self.root / "nonexistent.env"
        with mock.patch.dict(os.environ, {"INHERITED": "yes"}, clear=True), \
             mock.patch.object(zab.os, "execvpe") as mock_exec:
            zab.cmd_inner_launch("t1", "pi-agent", None, 100.0, "s1", ["pi-agent"], env_file=str(missing_file))
            self.assertEqual(os.environ["INHERITED"], "yes")
            mock_exec.assert_called_once()

if __name__ == "__main__":
    unittest.main()
