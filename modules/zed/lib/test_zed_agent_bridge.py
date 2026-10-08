#!/usr/bin/env python3
import json
import os
import sqlite3
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
        env = {"HOME": str(self.root), "XDG_STATE_HOME": str(self.root / "state")}
        self._env = mock.patch.dict(os.environ, env)
        self._env.start()

    def tearDown(self):
        self._env.stop()
        self._tmp.cleanup()


class StateTest(TmpHome):
    def test_roundtrip(self):
        zab.write_state("t1", "claude", "s1")
        self.assertEqual(zab.read_state("t1"), {"agent": "claude", "session_id": "s1"})

    def test_missing_state_is_none(self):
        self.assertIsNone(zab.read_state("nope"))

    def test_claimed_by_other(self):
        zab.write_state("t1", "prime-agent", "s1")
        self.assertTrue(zab.claimed_by_other("s1", "t2"))
        self.assertFalse(zab.claimed_by_other("s1", "t1"))
        self.assertFalse(zab.claimed_by_other("s2", "t2"))


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
    def _prime(self, sid, cwd, mtime):
        d = self.root / ".config/prime-agent/sessions"
        d.mkdir(parents=True, exist_ok=True)
        p = d / f"{sid}.jsonl"
        p.write_text(json.dumps({"type": "session", "id": sid, "cwd": cwd}) + "\n")
        os.utime(p, (mtime, mtime))

    def test_claude_exists(self):
        d = self.root / ".claude/projects/-home-x"
        d.mkdir(parents=True)
        (d / "s1.jsonl").write_text("{}\n")
        self.assertTrue(zab.LOCATORS["claude"]["exists"]("s1"))
        self.assertFalse(zab.LOCATORS["claude"]["exists"]("s2"))

    def test_prime_latest_picks_newest_in_cwd_after_since(self):
        now = time.time()
        self._prime("old", "/p", now - 100)
        self._prime("new", "/p", now - 5)
        self._prime("newer-other-cwd", "/q", now)
        latest = zab.LOCATORS["prime-agent"]["latest"]
        self.assertEqual(latest("/p", now - 50), "new")
        self.assertIsNone(latest("/p", now + 10))
        self.assertTrue(zab.LOCATORS["prime-agent"]["exists"]("old"))

    def test_antigravity_latest(self):
        d = self.root / ".gemini/antigravity-cli"
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

    def test_watch_once_records_unclaimed_session(self):
        zab.write_state("other", "prime-agent", "taken")
        latest = lambda cwd, since: "taken"
        self.assertIsNone(zab.watch_once("t1", "prime-agent", latest, "/p", 0, None))
        latest = lambda cwd, since: "mine"
        self.assertEqual(zab.watch_once("t1", "prime-agent", latest, "/p", 0, None), "mine")
        self.assertEqual(zab.read_state("t1")["session_id"], "mine")


CFG = {
    "defaultAgent": "claude",
    "agents": {
        "claude": {"command": ["claude"], "resumeArgs": ["--resume", "{id}"], "locator": "claude"},
        "prime-agent": {"command": ["prime-agent"], "resumeArgs": ["--resume", "{id}"], "locator": "prime-agent"},
    },
}
FAKE_LOCATORS = {
    "claude": {"exists": lambda s: s == "alive", "latest": None},
    "prime-agent": {"exists": lambda s: s == "alive", "latest": None},
}


class LaunchTest(TmpHome):
    def test_no_state_starts_default(self):
        self.assertEqual(zab.plan_launch(CFG, None, FAKE_LOCATORS), ("claude", ["claude"], None))

    def test_state_resumes_recorded_agent(self):
        state = {"agent": "prime-agent", "session_id": "alive"}
        self.assertEqual(
            zab.plan_launch(CFG, state, FAKE_LOCATORS),
            ("prime-agent", ["prime-agent", "--resume", "alive"], "alive"),
        )

    def test_deleted_session_starts_default(self):
        state = {"agent": "prime-agent", "session_id": "gone"}
        self.assertEqual(zab.plan_launch(CFG, state, FAKE_LOCATORS)[1], ["claude"])

    def test_unknown_agent_starts_default(self):
        state = {"agent": "removed", "session_id": "alive"}
        self.assertEqual(zab.plan_launch(CFG, state, FAKE_LOCATORS)[1], ["claude"])

    def test_missing_default_agent_starts_bare_command(self):
        cfg = {"defaultAgent": "claude", "agents": {}}
        self.assertEqual(zab.plan_launch(cfg, None, FAKE_LOCATORS), ("claude", ["claude"], None))

    def test_no_state_and_empty_default_prompts_selector(self):
        cfg = {"defaultAgent": "", "agents": CFG["agents"]}
        picker = lambda c: "prime-agent"
        self.assertEqual(
            zab.plan_launch(cfg, None, FAKE_LOCATORS, picker=picker),
            ("prime-agent", ["prime-agent"], None),
        )

    def test_no_state_and_agents_default_prompts_selector(self):
        cfg = {"defaultAgent": "agents", "agents": CFG["agents"]}
        picker = lambda c: "prime-agent"
        self.assertEqual(
            zab.plan_launch(cfg, None, FAKE_LOCATORS, picker=picker),
            ("prime-agent", ["prime-agent"], None),
        )

    def test_selector_cancelled_returns_none(self):
        cfg = {"defaultAgent": "", "agents": CFG["agents"]}
        picker = lambda c: None
        self.assertEqual(
            zab.plan_launch(cfg, None, FAKE_LOCATORS, picker=picker),
            (None, None, None),
        )

    def test_state_resumes_recorded_agent_without_picker(self):
        cfg = {"defaultAgent": "", "agents": CFG["agents"]}
        state = {"agent": "prime-agent", "session_id": "alive"}
        picker = mock.Mock()
        self.assertEqual(
            zab.plan_launch(cfg, state, FAKE_LOCATORS, picker=picker),
            ("prime-agent", ["prime-agent", "--resume", "alive"], "alive"),
        )
        picker.assert_not_called()

    def test_plan_launch_deduplicates_concatenated_command(self):
        cfg = {"defaultAgent": "claude", "agents": {"claude": {"command": ["claude", "claude"]}}}
        self.assertEqual(zab.plan_launch(cfg, None, FAKE_LOCATORS), ("claude", ["claude"], None))

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
        self._hook({zab.ENV_ID: "t1", zab.ENV_AGENT: "prime-agent", zab.ENV_PID: str(os.getpid())})
        self.assertIsNone(zab.read_state("t1"))


if __name__ == "__main__":
    unittest.main()
