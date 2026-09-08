// zen 429s unless identified as an opencode client, and since 2026-09-06 400s
// free-tier requests carrying no session header.

import { randomUUID } from "node:crypto";
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

// models.json cannot mint an id per run (Nix eval has no RNG), so the opencode
// headers live here instead. @opencodeVersion@ is substituted at build time.
const USER_AGENT = "opencode/@opencodeVersion@";

export default function zenSession(pi: ExtensionAPI) {
  let current = "";

  // registerProvider replaces the stored provider request config wholesale, so
  // the User-Agent has to be resent alongside every new session id.
  function useSessionId(sessionId: string): void {
    if (!sessionId || sessionId === current) return;
    current = sessionId;
    pi.registerProvider("opencode", {
      headers: {
        "User-Agent": USER_AGENT,
        "x-opencode-session": sessionId,
      },
    });
  }

  // Queued until the runner binds, so this covers a request made before the
  // first session_start.
  useSessionId(randomUUID());

  // pi session ids are uuidv7, the shape zen wants. session_tree catches the
  // switches and forks that reassign the id mid-process.
  const track = (_event: unknown, ctx: ExtensionContext) => {
    useSessionId(ctx.sessionManager.getSessionId());
  };

  pi.on("session_start", track);
  pi.on("session_tree", track);
}
