# Second, INDEPENDENT Sunshine instance that captures the real physical KDE Plasma
# (Wayland) desktop — the canonical Moonlight "Desktop" app — WITHOUT touching the
# headless gamescope instance.
#
# Why a whole second daemon (and not a prep-cmd / an extra app on the primary): the primary
# sunshine.service is hard-pinned to the private gamescope portal — WAYLAND_DISPLAY=
# gamescope-0 + a private D-Bus bus, baked into its process env at startup. A prep-cmd is a
# CHILD of that daemon and cannot rewrite the running parent's env, and Sunshine's capture
# backend/display is a single global per daemon — so one daemon serves gamescope OR the real
# Plasma portal, never both. This instance simply OMITS the gamescope env override, so it
# inherits the real graphical-session env (wayland-0 + the real user bus) and captures KWin's
# ScreenCast portal. It runs on its own ports and its own isolated state dir (redirected
# XDG_CONFIG_HOME), so it pairs independently and never collides with the primary.
{
  pkgs,
  lib,
  cfg, # icedos.applications.steam.headlessSession.desktopCapture
}:

let
  inherit (cfg)
    name
    port
    backend
    outputName
    ;

  # One "Desktop" app, no `cmd` → Sunshine streams the live desktop for the whole session.
  # The top-level `env` node is REQUIRED: Sunshine's apps parser aborts with
  # "No such node (env)" and loads ZERO apps when it is missing (the stock apps.json always
  # carries it). image-path "desktop.png" is Sunshine's bundled asset (resolved from its
  # assets dir), matching the stock apps.json.
  appsJson = pkgs.writeText "sunshine-desktop-apps.json" (
    builtins.toJSON {
      env = {
        PATH = "$(PATH):$(HOME)/.local/bin";
      };
      apps = [
        {
          name = "Desktop";
          "image-path" = "desktop.png";
        }
      ];
    }
  );

  # Minimal Sunshine config, same shape as the nixpkgs-generated one. State (pairing, TLS
  # certs, log) is deliberately NOT set here: Sunshine resolves it under $XDG_CONFIG_HOME/
  # sunshine, and the service redirects XDG_CONFIG_HOME to an isolated dir (see below), so the
  # desktop instance's state lands apart from the primary's ~/.config/sunshine.
  sunshineConf = pkgs.writeText "sunshine-desktop.conf" (
    ''
      sunshine_name=${name}
      port=${toString port}
      capture=${backend}
      file_apps=${appsJson}
    ''
    + lib.optionalString (outputName != "") "output_name=${outputName}\n"
  );

  # portal capture needs no elevated caps (the primary runs the bare binary the same way);
  # kms grabs the raw DRM scanout and needs CAP_SYS_ADMIN → the setcap wrapper the base
  # sunshine module installs when icedos.applications.sunshine.capSysAdmin = true (asserted
  # in icedos.nix).
  sunshineBin =
    if backend == "kms" then "/run/wrappers/bin/sunshine" else "${pkgs.sunshine}/bin/sunshine";

  # Sunshine derives its whole port block from the base `port`; open the same offsets the
  # primary uses (relative to its 47989 base), shifted to this instance's base.
  firewall = {
    allowedTCPPorts = [
      (port - 5) # HTTPS
      port # HTTP
      (port + 1) # Web UI
      (port + 21) # RTSP
    ];
    allowedUDPPorts = [
      (port + 9) # Video
      (port + 10) # Control
      (port + 11) # Audio
      (port + 13) # Mic
    ];
  };

  service = {
    description = "Sunshine (physical desktop capture) for Moonlight";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];

    # No WAYLAND_DISPLAY / DBUS_SESSION_BUS_ADDRESS override → inherit the REAL Plasma
    # Wayland session (wayland-0 + the real user bus), so capture=portal reaches KWin's
    # xdg-desktop-portal-kde ScreenCast. XDG_CONFIG_HOME is redirected so this instance's
    # pairing state / certs / log live apart from the primary's ~/.config/sunshine — and its
    # portal restore token is KEPT (unlike the primary's, which is wiped each start), so KDE's
    # one-time "share this screen" pick is remembered across streams.
    environment.XDG_CONFIG_HOME = "%h/.config/sunshine-desktop";

    serviceConfig = {
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/.config/sunshine-desktop/sunshine";
      ExecStart = "${sunshineBin} ${sunshineConf}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
in
{
  inherit service firewall;
}
