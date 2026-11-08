# IceDOS apps

Application modules for the IceDOS framework.

## Usage

Modules in IceDOS do not have an `enable` option. To enable a module, add its name to this repository's `modules` list in your configuration (e.g., `config.toml`):

```toml
[[icedos.repositories]]
url = "github:icedos/apps"
# fetchDependencies = true         # default: true, fetches required module dependencies
# fetchOptionalDependencies = false # default: false, set to true to fetch optional dependencies
modules = [
  "btop",
  "kitty",
  "neovim",
]
```

Dependencies declared across IceDOS repositories are fetched automatically. If you set `fetchDependencies = false` on this repository, you must declare and add any cross-repository dependencies yourself.

## Default module

The `default` module always loads when this repository is included in your configuration. It provisions system utilities and pulls in baseline dependencies:

### Baseline packages and settings

Always active, even if `fetchDependencies = false`:

- **Packages**: `efibootmgr`, `killall`, `ntfs3g`, `p7zip`, `unrar`, `unzip`, `wget`
- **Settings**: Disables `programs.nano`

### Automatically loaded dependencies

Skipped if `fetchDependencies = false`:

- [`direnv`](modules/direnv/icedos.nix): Directory-based environment variable switcher (`.envrc`)
- [`nix-health`](modules/nix-health/icedos.nix): Diagnostic check tool for Nix and NixOS system health
- [`toolset`](modules/toolset/icedos.nix): Download and IP toolset utilities

### Optional dependencies

Loaded only when `fetchOptionalDependencies = true` on this repository entry (which defaults to `false`), provided `fetchDependencies` is not `false`:

- [`kitty`](modules/kitty/icedos.nix): GPU-accelerated terminal emulator
- [`neovim`](modules/neovim/icedos.nix): Extensible text editor

## Exposed modules

| Module | Path | Description |
| :--- | :--- | :--- |
| `ambiled` | [modules/ambiled/icedos.nix](modules/ambiled/icedos.nix) | Screen-synchronized ambient backlighting tool |
| `android-tools` | [modules/android-tools/icedos.nix](modules/android-tools/icedos.nix) | Android Debug Bridge (adb) CLI utilities and text-paste helper |
| `btop` | [modules/btop/icedos.nix](modules/btop/icedos.nix) | Resource monitor showing CPU, memory, disk, network, and process usage |
| `celluloid` | [modules/celluloid/icedos.nix](modules/celluloid/icedos.nix) | GTK frontend for MPV media player with AMD FSR upscaling shader |
| `codium` | [modules/editors/codium/icedos.nix](modules/editors/codium/icedos.nix) | VSCodium open-source code editor with customizable user settings |
| `craft-anything` | [modules/artcraft/craft-anything/icedos.nix](modules/artcraft/craft-anything/icedos.nix) | Open-source tool to study how software works and build your own version |
| `designcraft` | [modules/artcraft/designcraft/icedos.nix](modules/artcraft/designcraft/icedos.nix) | Open-source page layout and publishing in pure Rust |
| `direnv` | [modules/direnv/icedos.nix](modules/direnv/icedos.nix) | Environment variable switcher based on current directory (.envrc) |
| `effectcraft` | [modules/artcraft/effectcraft/icedos.nix](modules/artcraft/effectcraft/icedos.nix) | Open-source motion graphics and visual effects in pure Rust |
| `figcraft` | [modules/artcraft/figcraft/icedos.nix](modules/artcraft/figcraft/icedos.nix) | Open-source UI design and prototyping tool (clean-room Figma-style) in pure Rust |
| `filmcraft` | [modules/artcraft/filmcraft/icedos.nix](modules/artcraft/filmcraft/icedos.nix) | Open-source video editor (clean-room Premiere Pro-style) in pure Rust |
| `flatpak` | [modules/flatpak/icedos.nix](modules/flatpak/icedos.nix) | Flatpak application sandboxing service and Flathub repository setup |
| `gnome-control-center` | [modules/gnome-control-center/icedos.nix](modules/gnome-control-center/icedos.nix) | GNOME Control Center configuration and settings app |
| `helium` | [modules/browsers/helium/icedos.nix](modules/browsers/helium/icedos.nix) | Privacy-focused Helium web browser with custom profile shortcuts |
| `input-remapper` | [modules/input-remapper/icedos.nix](modules/input-remapper/icedos.nix) | Input device button, key, and axis remapping daemon |
| `kitty` | [modules/kitty/icedos.nix](modules/kitty/icedos.nix) | GPU-accelerated terminal emulator with custom fonts and themes |
| `lact` | [modules/lact/icedos.nix](modules/lact/icedos.nix) | Linux GPU overclocking, fan curve, and power management |
| `librewolf` | [modules/browsers/librewolf/icedos.nix](modules/browsers/librewolf/icedos.nix) | Privacy and security-focused fork of Firefox |
| `materialcraft` | [modules/artcraft/materialcraft/icedos.nix](modules/artcraft/materialcraft/icedos.nix) | Open-source, node-based procedural material designer in pure Rust |
| `nautilus` | [modules/nautilus/icedos.nix](modules/nautilus/icedos.nix) | GNOME file manager with GVFS and trash integration |
| `ncdu` | [modules/ncdu/icedos.nix](modules/ncdu/icedos.nix) | NCurses disk usage analyzer integrated into the icedos toolset |
| `neovim` | [modules/neovim/icedos.nix](modules/neovim/icedos.nix) | Vim-fork text editor focused on extensibility and usability |
| `nix-alien` | [modules/nix-alien/icedos.nix](modules/nix-alien/icedos.nix) | Run unpatched Linux binaries on NixOS without packaging |
| `nix-health` | [modules/nix-health/icedos.nix](modules/nix-health/icedos.nix) | Diagnostic check tool for Nix and NixOS environment health |
| `obs` | [modules/obs/icedos.nix](modules/obs/icedos.nix) | OBS Studio screen recorder and livestreamer with plugin support |
| `protonvpn-cli` | [modules/protonvpn-cli/icedos.nix](modules/protonvpn-cli/icedos.nix) | Proton VPN CLI service with optional KDE Plasma tray/widget |
| `sd-inhibitor` | [modules/sd-inhibitor/icedos.nix](modules/sd-inhibitor/icedos.nix) | Systemd idle, sleep, and shutdown inhibitor with activity watchers |
| `simpmusic` | [modules/music/simpmusic/icedos.nix](modules/music/simpmusic/icedos.nix) | Cross-platform music app using YouTube Music for backend |
| `solaar` | [modules/solaar/icedos.nix](modules/solaar/icedos.nix) | Device manager for Logitech wireless mice, keyboards, and unifying receivers |
| `spotube` | [modules/music/spotube/icedos.nix](modules/music/spotube/icedos.nix) | Open-source music client with plugin-based audio and metadata sources |
| `steam` | [modules/steam/icedos.nix](modules/steam/icedos.nix) | Steam gaming platform with hardware support, download, and CPU tweaks |
| `steam-headless` | [modules/steam/modules/steam-headless/icedos.nix](modules/steam/modules/steam-headless/icedos.nix) | Headless Steam Big Picture session streaming via Sunshine |
| `steam-session` | [modules/steam/modules/session/icedos.nix](modules/steam/modules/session/icedos.nix) | Dedicated Steam Gamescope Wayland compositor session |
| `steamos-session` | [modules/steam/modules/os-session/icedos.nix](modules/steam/modules/os-session/icedos.nix) | Jovian SteamOS Gamescope console session |
| `sunshine` | [modules/sunshine/icedos.nix](modules/sunshine/icedos.nix) | Self-hosted Moonlight game streaming host for desktop capture |
| `sunshine-headless` | [modules/sunshine/modules/sunshine-headless/icedos.nix](modules/sunshine/modules/sunshine-headless/icedos.nix) | Headless Sunshine streaming daemon |
| `tailscale` | [modules/tailscale/icedos.nix](modules/tailscale/icedos.nix) | Zero-config mesh VPN service with optional Trayscale GUI |
| `texturecraft` | [modules/artcraft/texturecraft/icedos.nix](modules/artcraft/texturecraft/icedos.nix) | Open-source 3D texture painting in pure Rust |
| `toolset` | [modules/toolset/icedos.nix](modules/toolset/icedos.nix) | Download and IP toolset utilities |
| `ubports-installer` | [modules/ubports-installer/icedos.nix](modules/ubports-installer/icedos.nix) | Install Ubuntu Touch on supported UBports mobile devices |
| `walker` | [modules/walker/icedos.nix](modules/walker/icedos.nix) | Application launcher, clipboard history, and menu runner with Elephant |
| `wg-quick` | [modules/wg-quick/icedos.nix](modules/wg-quick/icedos.nix) | WireGuard secure VPN tunnel service managed via wg-quick |
| `winboat` | [modules/winboat/icedos.nix](modules/winboat/icedos.nix) | Windows container runner with FreeRDP |
| `zed` | [modules/editors/zed/icedos.nix](modules/editors/zed/icedos.nix) | Code editor with agent bridge (requires agent-launch in ai-tools) |
