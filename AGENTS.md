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
- `modules/default/` declares the baseline dependency set (`direnv`, `nix-health`,
  `toolset`) via `meta.dependencies`.

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
- `peon-ping` — Warcraft-peon-style agent-event audio. **Standalone** module: owns
  `icedos.applications.peon-ping.users.<name>` (self-materialised via `genDefaults`).
  Claude Code integration is upstream's own `programs.peon-ping.claudeCodeIntegration`
  (per-user opt-in, `claudeCodeIntegration = true`), and `opencode` consumes the user
  settings for its own peon plugin. See core's *Per-user (`users`) options*.
- `me3` — game mod loader (per-game profiles/natives/packages).
- `sunshine` + `sunshine-headless` + `steam-headless` — game streaming, incl. headless
  HDR. The base `sunshine` module is always the primary, stock daemon (real desktop capture).
  Loading `sunshine-headless` stands up a SECOND, independent `sunshine-headless` daemon
  (own ports/state) pinned to a private gamescope-0 portal; autostart via its
  `icedos.applications.sunshine-headless.session.sunshine.autoStart`. The module is
  generic: `icedos.applications.sunshine-headless.apps` lists the apps it streams (each
  an argv `command` plus per-hook shell), and the helper records each app's process group
  instead of shipping per-app launcher derivations. `steam-headless` (under `steam/modules/`)
  only names Steam's sessions there: `icedos.applications.steam.headless-session`.
  Sunshine tokenizes the generated `cmd` and `prep-cmd` strings itself, with no shell, so
  nothing is expanded there: a name with a space must be double-quoted (the module does it,
  and an assertion rejects a name containing a double quote). Pads the client forwards are
  uinput evdev devices (only PS-type pads use `uhid` and gain a `/dev/hidraw*` node), and
  `isolateVirtual` strips their uaccess, leaving `root:input 0660`. A plain app still reads
  them because the daemon runs through `sunshine-headless-gid-root` and its children inherit
  the `input` group; the `shim` matters only for a process that does not descend from the
  daemon. `session.controllers.excludeHost` keeps host physical pads out of app scopes: the
  scope keeps the daemon's `input` group, because its processes are the daemon's children and
  inherit it, and the uaccess-stripped forwarded nodes `root:input 0660` need it; the cgroup
  device policy is what denies host pads. Such a scope is in no session either, so polkit
  refuses the idle/sleep and power-profile holds there (this module's rules let its marker group
  take them, and proton-launch drops a refused hold instead of dying).
- `gamescope`, `lsfg-vk`, `mangohud` — gaming/perf.
- `helium` — loads `inputs.nur.modules.nixos.default` (the input is supplied by
  `providers#nur` via `meta.dependencies`), which puts unvetted `pkgs.nur.repos.*`
  into the global package set. The only consumer of the NUR overlay today.
- `prefixer`, `proton-launch` — Proton prefix tooling (protontricks is deprecated here;
  use `prefixer <APP_ID> run <exe>`).
- `prime-agent` — mirrors the bundled models.dev catalog into `models.json`. Only models in
  that snapshot show up today (it lags upstream). To add a newly released model without waiting
  for a prime-agent bump, define it under `icedos.applications.prime-agent.settings.providers.<name>.models`:
  prime-agent's `models[]` **merges** with the catalog — an unknown id is added (inheriting the
  built-in provider's api/baseUrl), a known id replaces the bundled definition. Use the model's
  real dot id (e.g. `glm-5.3-flash`, not `glm-5-3-flash`) and the same id in `modelOverrides`.
