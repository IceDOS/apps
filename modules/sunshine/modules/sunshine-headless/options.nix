{ icedosLib, lib }:

let
  inherit (icedosLib)
    mkAttrsOfOption
    mkBoolOption
    mkEnumOption
    mkFloatBetweenOption
    mkIntBetweenOption
    mkLinesOption
    mkListOption
    mkNullableOption
    mkRecordOption
    mkStrListOption
    mkStrOption
    mkSubmoduleAttrsOption
    mkSubmoduleListOption
    ;

  inherit (lib) importTOML types;

  inherit ((importTOML ./config.toml).icedos.applications.sunshine-headless)
    apps
    session
    ;
in
{
  # The SECOND, independent Sunshine daemon streaming the headless gamescope session;
  # the primary stock daemon stays untouched. Consuming modules supply `apps`.

  # Apps published over Moonlight. A module wires its launcher in by appending entries
  # (see steam-headless/hooks.nix); users add plain commands of their own.
  apps = mkSubmoduleListOption { default = apps; } {
    # Sunshine app name: the Moonlight list entry and the key for start/wait/stop.
    name = mkStrOption { default = ""; };

    # Runtime file suffix (states, logs, scope unit); derived from `name` when empty.
    slug = mkStrOption { default = ""; };

    # Name of the compositor backend; "" uses session.defaultCompositor.
    compositor = mkStrOption { default = ""; };

    # Command run inside the session, as an argv list; empty only when every hook is supplied.
    command = mkStrListOption { default = [ ]; };

    # HOME for this app: "" = the streaming user, else e.g. a second Steam account.
    home = mkStrOption { default = ""; };

    # Moonlight cover art; "" leaves the app without one, so Sunshine serves its default.
    image-path = mkStrOption { default = ""; };

    # Extra environment for the launched app (e.g. QT_QPA_PLATFORM=xcb forces X11).
    # An empty string UNSETS the variable: env = { WAYLAND_DISPLAY = "" } makes any
    # toolkit fall back to X11 instead of connecting to the headless Wayland display.
    env = mkAttrsOfOption { default = { }; } types.str;

    # Publish a Sunshine app that waits on the session app instead of auto-detaching.
    auto-detach = mkBoolOption { default = false; };

    # Extra tools for the session helper's PATH (Steam, proton-launch, ...).
    packages = mkListOption { default = [ ]; } types.package;

    # Launch through the setgid-`input` shim: only steam-*/gamescope-* targets pass its
    # gate, so a plain app fails at exec. A plain app does not need it: it inherits the
    # daemon's `input` group, which is what opens the uaccess-stripped pads (see scripts.nix).
    shim = mkBoolOption { default = false; };

    # Run gamescope in --steam mode for this app (the Steam client and its games):
    # steamcompmgr's appid focus machinery. Plain apps get a normal compositor,
    # which presents any window without app ids.
    steamMode = mkBoolOption { default = false; };

    # Per-app gamescope overrides; null inherits the module-global gamescope.* value.
    # The session restarts gamescope with the incoming app's settings.
    # hdr/nativeWayland/inputInjection/mangoApp select patched builds, so an app can only
    # turn them on when the module-global option is on, and it can always turn them off.
    # A steamMode app cannot override nativeWayland or mangoApp (its environment is built at
    # evaluation time). sdrContentNits/sdrGamutWideness reach gamescope as CLI flags on an
    # HDR stream; the SDR-to-HDR mapping is substituted into the build from the globals.
    gamescope = mkRecordOption { default = { }; } {
      hdr = mkNullableOption { default = null; } types.bool;
      sdrContentNits = mkNullableOption { default = null; } types.int;
      sdrGamutWideness = mkNullableOption { default = null; } types.float;
      renderWidth = mkNullableOption { default = null; } types.int;
      renderHeight = mkNullableOption { default = null; } types.int;
      upscaleFilter = mkNullableOption { default = null; } types.str;
      fsrSharpness = mkNullableOption { default = null; } types.int;
      nativeWayland = mkNullableOption { default = null; } types.bool;
      inputInjection = mkNullableOption { default = null; } types.bool;
      mangoApp = mkNullableOption { default = null; } types.bool;
      realtime = mkNullableOption { default = null; } types.bool;
    };

    # Per-app session overrides; null inherits the module-global session.* value.
    # controllers.isolateVirtual has no per-app form: its udev rule, group and wrapper are
    # system state, and `shim` above is the per-app switch that uses them.
    session = mkRecordOption { default = { }; } {
      idleTimeout = mkNullableOption { default = null; } types.int;
      pauseOnDisconnect = mkNullableOption { default = null; } types.bool;
      controllers = mkRecordOption { default = { }; } {
        excludeHost = mkNullableOption { default = null; } types.bool;
      };
    };

    # Bash library emitted once, before the hooks (helper functions the hooks call).
    helpers = mkLinesOption { default = ""; };

    # Per-hook shell bodies; an empty hook falls back to the generic behaviour
    # (see scripts.nix): start = launch, alive = process group, stop = teardown.
    # Liveness is the process group of `command`, so a launcher that detaches its payload
    # (setsid, a daemonizing wrapper) must supply its own alive and stop hooks.
    hooks = mkRecordOption { default = { }; } {
      start = mkLinesOption { default = ""; };
      alive = mkLinesOption { default = ""; };
      pids = mkLinesOption { default = ""; };
      tick = mkLinesOption { default = ""; };
      stop = mkLinesOption { default = ""; };
      drain = mkLinesOption { default = ""; };
    };
  };

  # Compositor backends; each module adds one. See gaming#sunshine-headless-gamescope.
  compositors = mkSubmoduleAttrsOption { default = { }; } {
    # Socket name under $XDG_RUNTIME_DIR.
    waylandDisplay = mkStrOption { default = ""; };

    packages = mkListOption { default = [ ]; } types.package;

    # This backend consumes the libvirtualhid devices, so their uaccess must be stripped.
    inputBridge = mkBoolOption { default = false; };

    # Bash emitted once, before every hook and app helper.
    helpers = mkLinesOption { default = ""; };

    hooks = mkRecordOption { default = { }; } {
      setup = mkLinesOption { default = ""; };
      ensure = mkLinesOption { default = ""; };
      appEnv = mkLinesOption { default = ""; };
      waitReady = mkLinesOption { default = ""; };
      tick = mkLinesOption { default = ""; };
      release = mkLinesOption { default = ""; };
      probe = mkLinesOption { default = ""; };
      recycle = mkLinesOption { default = ""; };
    };

    portal = mkRecordOption { default = { }; } {
      # D-Bus activation directories for this backend's private bus.
      serviceDirs = mkStrListOption { default = [ ]; };
      # Inherited by services the bus activates.
      busEnvironment = mkAttrsOfOption { default = { }; } types.str;
      environment = mkAttrsOfOption { default = { }; } types.str;
      # false: the backend starts the portal itself once its compositor is up.
      autoStart = mkBoolOption { default = true; };
    };
  };

  session = {
    # Backend for apps that name none and for Sunshine's startup probe; "" prefers gamescope.
    defaultCompositor = mkStrOption { default = session.defaultCompositor; };

    # Freeze the per-app cgroup (SIGSTOP) ~10s after the last client disconnects;
    # thaw on reconnect. Off = keep running idle.
    pauseOnDisconnect = mkBoolOption { default = session.pauseOnDisconnect; };

    # Seconds with no active stream before the session is torn down (apps + the full
    # gamescope); the minimal probe gamescope regrows on its own timer. 0 = off.
    idleTimeout = mkIntBetweenOption {
      path = "icedos.applications.sunshine-headless.session.idleTimeout";
      source = ./config.toml;
      default = session.idleTimeout;
    } 0 86400;

    controllers = {
      # Keep host physical controllers out of the session apps (see scripts.nix).
      excludeHost = mkBoolOption { default = session.controllers.excludeHost; };

      # Hide the Sunshine virtual pad from the host desktop (see scripts.nix).
      isolateVirtual = mkBoolOption { default = session.controllers.isolateVirtual; };
    };

    sunshine = {
      # Start at the graphical session (like the primary's autoStart); false = manual.
      autoStart = mkBoolOption { default = session.sunshine.autoStart; };

      # desktopShortcut: app-menu entry that starts the headless daemon (portal +
      # idle gamescope gate); the overlay derives it from the shipped shortcut.
      desktopShortcut = mkBoolOption { default = session.sunshine.desktopShortcut; };

      # mDNS label; must differ from the primary.
      name = mkStrOption { default = session.sunshine.name; };

      # Base port for the headless instance (primary uses 47989); Sunshine derives its whole block from it.
      port = mkIntBetweenOption {
        path = "icedos.applications.sunshine-headless.session.sunshine.port";
        source = ./config.toml;
        default = session.sunshine.port;
      } 1024 65535;

      # Open the headless instance's derived TCP/UDP port block in the host firewall.
      openFirewall = mkBoolOption { default = session.sunshine.openFirewall; };

      # Pad Sunshine emulates on the host. `auto` follows the client's reported pad type, which
      # is the default behaviour; the rest pin one type for every stream, because Sunshine
      # parses `gamepad` once for the daemon and has no per-app pad type. Eden is the known
      # case that wants a Switch Pro pad; `ds5` needs /dev/uhid, see the module's udev rules.
      gamepad =
        mkEnumOption
          {
            path = "icedos.applications.sunshine-headless.session.sunshine.gamepad";
            source = ./config.toml;
            default = session.sunshine.gamepad;
          }
          [
            "auto"
            "generic"
            "ds5"
            "switch"
            "xone"
          ];
    };
  };
}
