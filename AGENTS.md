# AGENTS.md — IceDOS **apps**

> Utilizes the **IceDOS** framework. The full bible — module structure, config flow,
> the `icedos rebuild --build` test loop, `validate.*` helpers, dep loading — lives in
> **core**: <https://github.com/IceDOS/core/blob/main/AGENTS.md> — this file only
> covers what is specific to **apps**.

## Non-negotiable rules (full detail in core)
- Build/test only via the `icedos` CLI — **never `sudo nixos-rebuild`**.
- **Never** `git commit/stash/reset/pull` — the user manages git.
- Every option uses a `validate.*`/`mk*Option` helper; **no untyped options**.
- A module's `config.toml` defaults must mirror its `icedos.nix` defaults.
- Format with `icedos nixf .` after editing any `.nix`.
- If a repo or the config root you need isn't checked out locally, **ask the user** for
  its path or permission to `git clone` it — don't guess or clone unprompted.

## Purpose
Application modules — the bulk of what a user installs and configures: terminals,
browsers, gaming tooling, media apps, streaming, networking, dev tools. ~70 modules.

## Layout
- `modules/<name>/{icedos.nix,config.toml}` per module; `flake.nix` exposes them via
  `icedosLib.scanModules { path = ./modules; filename = "icedos.nix"; }`.
- `modules/default/` declares the baseline dependency set (`bash`, `git`, `direnv`,
  `zsh`, `ssh`, `nix-health`) via `meta.dependencies`.

## Module shape here
Standard IceDOS module: `options.icedos.applications.<name>` (defaults read from the
sibling `config.toml`), `outputs.nixosModules = { ... }: [ … ]`, `meta.name`. See the
btop walk-through in the core bible.

**There is no `enable` option.** A module is enabled by appearing in the apps repo's
`modules = [ … ]` list in the config root's `config.toml` — except modules that load
automatically as `dependencies`/`optionalDependencies` of the repo's `default` module.

## Test a change to this repo
In the config root's `config.toml`, point this repo's `overrideUrl` at your local
checkout (`path:/abs/path/to/apps`), then `icedos rebuild --build` (no activation).
`path:` inputs auto-refresh each build.

## Notable modules / gotchas
- `me3` — game mod loader (per-game profiles/natives/packages).
- `sunshine` + `steam-sunshine-headless-session` — game streaming, incl. headless HDR.
- `gamescope`, `low-latency-vulkan-layer`, `lsfg-vk`, `mangohud`, `scx` — gaming/perf.
- `prefixer`, `proton-launch` — Proton prefix tooling (protontricks is deprecated here;
  use `prefixer <APP_ID> run <exe>`).
