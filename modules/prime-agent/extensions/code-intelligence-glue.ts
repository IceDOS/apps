// Pointer-only glue: tells models to load the matching per-language skill; the
// skills hold the actual nix-shell LSP commands, so nothing is duplicated here.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const GLUE = `
CODE INTELLIGENCE (always available on this NixOS box):
- Pull any language server ad hoc: nix-shell -p <pkg> --run "<tool> ...".
- For definitions, references, hover, diagnostics, or symbol search, load the
  per-language skill matching the code's language from the bundled
  code-intelligence set (bash, c-cpp, javascript, nix, python, typescript) and
  follow its exact commands; do not guess tool output.
- No skill for the language (e.g. Go, Rust, Lua): nix-shell -p gopls --run
  "gopls check ./...", rust-analyzer, or lua-language-server --check ./src.`;

export default function codeIntelligenceGlue(pi: ExtensionAPI) {
  pi.on("before_agent_start", (event) => {
    return {
      systemPrompt: `${event.systemPrompt}

${GLUE}`,
    };
  });
}
