// Loads the local llama.cpp server when a model it serves is about to be used,
// and stops it once the server itself reports every slot idle. The model is most
// of the card's VRAM, so leaving it resident blocks other GPU work.
//
// Idleness comes from the server's /slots endpoint, never from this extension's
// own view of the conversation. An earlier version timed idleness from agent
// events and killed generations mid-stream, because a long generation looks
// identical to an idle session from out here. is_processing does not.
//
// The llamacppUrl / llamacppBin / llamacppProvider / llamacppIdleSeconds values
// below are substituted at build time (the @ markers
// are the substitution syntax, so they are not repeated in prose here).

import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdirSync, readdirSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const URL_BASE = "@llamacppUrl@";
const BIN = "@llamacppBin@";
const PROVIDER = "@llamacppProvider@";
const IDLE_MS = Number("@llamacppIdleSeconds@") * 1000;

// Loading a 27B model off disk takes tens of seconds; well under this.
const START_TIMEOUT_MS = 180_000;
const PROBE_TIMEOUT_MS = 2_000;
const POLL_MS = 1_000;
const IDLE_CHECK_MS = 15_000;
// After a failed start, fail fast for a while instead of making every request
// sit through the full start timeout again.
const FAILURE_BACKOFF_MS = 60_000;
// An instance whose marker is older than this crashed without cleaning up.
const INSTANCE_STALE_MS = 120_000;

// The daemon spawns subagent runtimes in the same process and re-loads the
// extensions for each, and tearing one down emits session_shutdown with
// reason "quit" — indistinguishable from the user actually quitting. So
// "is anyone still using this?" has to be answered by counting live instances
// rather than by trusting the reason.
const INSTANCE = `${process.pid}-${randomUUID()}`;
const instanceDir = () =>
  join(
    process.env.PRIME_AGENT_CODING_AGENT_DIR ?? join(homedir(), ".config", "prime-agent"),
    "llamacpp-lifecycle",
    "instances",
  );
const registerInstance = () => {
  try {
    mkdirSync(instanceDir(), { recursive: true });
    writeFileSync(join(instanceDir(), INSTANCE), String(Date.now()));
  } catch {
    // ignore
  }
};
const unregisterInstance = () => {
  try {
    unlinkSync(join(instanceDir(), INSTANCE));
  } catch {
    // ignore
  }
};
const markerAlive = (name: string): boolean => {
  const pid = Number(name.split("-")[0]);
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (e: any) {
    return e?.code === "EPERM"; // exists, owned by another user
  }
};
// Counts instances other than this one that are actually using the local
// model, reaping markers left by crashes. A marker is only written while a
// session is on the local provider, so a cloud-only window cannot pin the
// model in VRAM.
const otherInstances = (): number => {
  let n = 0;
  try {
    for (const f of readdirSync(instanceDir())) {
      if (f === INSTANCE) continue;
      const path = join(instanceDir(), f);
      try {
        // Age alone would keep a SIGKILLed window counted for two minutes,
        // and nothing would run again to free the VRAM.
        if (!markerAlive(f) || Date.now() - statSync(path).mtimeMs > INSTANCE_STALE_MS) {
          unlinkSync(path);
          continue;
        }
      } catch {
        continue;
      }
      n += 1;
    }
  } catch {
    return 0;
  }
  return n;
};

export default function (pi: ExtensionAPI) {
  let enabled = true;
  let idleTimer: ReturnType<typeof setInterval> | null = null;
  let starting: Promise<boolean> | null = null;
  let failedUntil = 0;
  let lastBusyAt = Date.now();

  const get = async (path: string): Promise<Response | null> => {
    try {
      const res = await fetch(`${URL_BASE}${path}`, {
        signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
      });
      return res.ok ? res : null;
    } catch {
      return null;
    }
  };
  const healthy = async () => (await get("/health")) !== null;

  // null when the server can't be reached or the shape is unexpected — the
  // caller must treat that as "not known to be idle" rather than as idle.
  const allSlotsIdle = async (): Promise<boolean | null> => {
    const res = await get("/slots");
    if (!res) return null;
    try {
      const slots = await res.json();
      if (!Array.isArray(slots) || slots.length === 0) return null;
      return slots.every((s: any) => s?.is_processing === false);
    } catch {
      return null;
    }
  };

  const run = (args: string[]) => {
    try {
      const child = spawn(BIN, args, { detached: true, stdio: "ignore" });
      child.on("error", () => {});
      child.unref();
    } catch {
      // ignore
    }
  };

  // `starting` is assigned synchronously before the first await, so two hooks
  // firing together share one promise instead of racing two servers up.
  const ensureUp = async (notify?: (s: string) => void): Promise<boolean> => {
    if (starting) return starting;
    if (Date.now() < failedUntil) return false;
    const attempt = (async () => {
      if (await healthy()) {
        lastBusyAt = Date.now();
        return true;
      }
      notify?.("llamacpp: loading model…");
      run(["llamacpp", "serve", "--detached"]);
      const deadline = Date.now() + START_TIMEOUT_MS;
      while (Date.now() < deadline) {
        // unref'd: a start that never succeeds must not keep the process alive
        // for the full timeout after the user has quit.
        await new Promise((r) => {
          const t = setTimeout(r, POLL_MS);
          t.unref?.();
        });
        if (await healthy()) {
          lastBusyAt = Date.now();
          notify?.("llamacpp: ready");
          return true;
        }
      }
      failedUntil = Date.now() + FAILURE_BACKOFF_MS;
      notify?.("llamacpp: failed to start");
      return false;
    })();
    starting = attempt;
    try {
      return await attempt;
    } finally {
      if (starting === attempt) starting = null;
    }
  };

  const startIdleWatch = () => {
    // After the guard: with the poller disabled there is nothing to advertise,
    // and a marker nobody refreshes would just be reaped by another window.
    if (idleTimer || IDLE_MS <= 0) return;
    registerInstance();
    idleTimer = setInterval(async () => {
      if (!enabled || starting) return;
      const idle = await allSlotsIdle();
      // Unreachable, or still loading: either way, not a moment to stop it.
      if (idle !== true) {
        if (idle === false) lastBusyAt = Date.now();
        return;
      }
      if (Date.now() - lastBusyAt < IDLE_MS) return;
      run(["llamacpp", "stop"]);
      lastBusyAt = Date.now();
    }, IDLE_CHECK_MS);
    idleTimer.unref?.();
  };
  const stopIdleWatch = () => {
    unregisterInstance();
    if (!idleTimer) return;
    clearInterval(idleTimer);
    idleTimer = null;
  };
  // Tearing the poller down leaves nobody to free the VRAM, so hand it one
  // last chance: stop the server if it is up and genuinely idle. Never on a
  // busy one — is_processing is the server's own answer.
  const stopIfIdle = async () => {
    if (IDLE_MS <= 0) return;
    if ((await allSlotsIdle()) === true) run(["llamacpp", "stop"]);
  };

  // The request payload carries a bare model id, not "provider/id", so the
  // provider has to come from the registry.
  const isLocal = (ctx: any, id?: unknown): boolean => {
    if (typeof id === "string" && id) {
      try {
        // find(), not a getAll() scan: built-ins are listed before custom
        // models, so an id shared with a cloud built-in would resolve to the
        // cloud entry and the server would never be started.
        if (ctx?.modelRegistry?.find?.(PROVIDER, id)) return true;
      } catch {
        // registry unavailable; fall through to the session's model
      }
    }
    return ctx?.model?.provider === PROVIDER;
  };
  const notifier = (ctx: any) => (s: string) => ctx?.ui?.notify?.(s);

  // -- hooks ----------------------------------------------------------------
  // Start the load as soon as the model is chosen, but do NOT await it here.
  // Both of these run inside a daemon RPC (set_model) that times out well
  // before a ~35 s cold load finishes, which fails the selection itself. The
  // request path below waits on the same promise instead.
  const beginLoad = (ctx: any) => {
    void ensureUp(notifier(ctx)).catch(() => {});
  };
  // Refreshes the marker only while one exists; registerInstance is called
  // from startIdleWatch, so a cloud-only session never registers at all.
  const heartbeat = setInterval(() => {
    if (idleTimer) registerInstance();
  }, 30_000);
  heartbeat.unref?.();

  pi.on("session_start", async (_e: any, ctx: any) => {
    if (!enabled || !isLocal(ctx)) return;
    startIdleWatch();
    beginLoad(ctx);
  });
  pi.on("model_select", async (event: any, ctx: any) => {
    if (!enabled || !isLocal(ctx)) {
      stopIdleWatch();
      // Only when actually leaving the local model, and only if no other
      // session is still using it — a cloud-to-cloud switch must not stop a
      // server this session never touched.
      if (
        enabled &&
        event?.previousModel?.provider === PROVIDER &&
        otherInstances() === 0
      ) {
        await stopIfIdle();
      }
      return;
    }
    startIdleWatch();
    beginLoad(ctx);
  });
  // Blocking here is deliberate: the request would otherwise hit a closed port
  // while the model loads. The provider's own retries give up long before the
  // ~35 s a cold load takes.
  pi.on("before_provider_request", async (event: any, ctx: any) => {
    if (!enabled || !isLocal(ctx, event?.payload?.model)) return;
    lastBusyAt = Date.now();
    startIdleWatch();
    await ensureUp(notifier(ctx));
  });

  // Fires for "reload", "new" and "fork" as well as "quit", and each of those
  // re-evaluates this module into fresh closures while leaving the old ones'
  // timers running — nothing invalidates them — so the poller must be cleared
  // unconditionally or they accumulate one per reload.
  pi.on("session_shutdown", async (event: any) => {
    stopIdleWatch();
    clearInterval(heartbeat);
    unregisterInstance();
    // "quit" is also what a finishing subagent reports, so the reason alone
    // would unload the model on every Task spawn and make the parent's next
    // turn pay a ~35 s reload. Stop only when nobody else is left.
    if (enabled && event?.reason === "quit" && otherInstances() === 0) {
      await stopIfIdle();
    }
  });

  pi.registerCommand("unload-llamacpp", {
    description: "Stop the local llama.cpp server and free its VRAM",
    handler: async (_args: any, ctx: any) => {
      run(["llamacpp", "stop"]);
      ctx?.ui?.notify?.("llamacpp: stopped");
    },
  });
  pi.registerCommand("load-llamacpp", {
    description: "Start the local llama.cpp server",
    handler: async (_args: any, ctx: any) => {
      failedUntil = 0;
      const ok = await ensureUp(notifier(ctx));
      if (!ok) ctx?.ui?.notify?.("llamacpp: failed to start");
    },
  });
  pi.registerCommand("llamacpp-autostop", {
    description: "Toggle automatic llama.cpp start/stop",
    handler: async (_args: any, ctx: any) => {
      enabled = !enabled;
      if (!enabled) stopIdleWatch();
      else if (isLocal(ctx)) startIdleWatch();
      ctx?.ui?.notify?.(`llamacpp autostop: ${enabled ? "on" : "off"}`);
    },
  });
}
