# The nightly channel is a different application from the stable release: upstream
# rewrote spotube from Flutter to Compose Multiplatform, so its .deb is a jpackage bundle
# — bundled JRE, Skiko for rendering, vlcj for playback — laid out under /opt rather than
# /usr. Every part of nixpkgs' derivation that is specific to the Flutter build (the
# `cp -r usr/*` install, the GTK/webkitgtk deps, the mpv wrapper) therefore has to be
# replaced. All of them are plain attributes, so `overrideAttrs` still covers it and the
# pin in ./source.json stays the only thing ./update.sh has to touch.
{
  nixpkgs.overlays = [
    (
      final: prev:

      let
        inherit (final) lib;
        source = builtins.fromJSON (builtins.readFile ./source.json);
      in
      {
        spotube = prev.spotube.overrideAttrs (_: {
          inherit (source) version;

          src = final.fetchurl { inherit (source) url hash; };

          # jpackage resolves lib/app/<launcher>.cfg relative to the launcher in bin/, so
          # the bundle is copied wholesale and bin/ and lib/ stay siblings.
          installPhase = ''
            runHook preInstall

            mkdir -p $out/share/spotube
            cp -r opt/dev.krtirtho.spotube/. $out/share/spotube/

            for icon in usr/share/icons/hicolor/*/apps/dev.krtirtho.spotube.png; do
              install -Dm644 "$icon" "$out/''${icon#usr/}"
            done

            # The packaged entry has a reverse-DNS name, placeholder comment and category,
            # and an absolute /opt path that does not exist here.
            mkdir -p $out/share/applications
            substitute usr/share/applications/dev.krtirtho.spotube.desktop \
              $out/share/applications/spotube.desktop \
              --replace-fail "Name=dev.krtirtho.spotube" "Name=Spotube" \
              --replace-fail "Comment=Packaged desktop application" "Comment=Open source Spotify client" \
              --replace-fail "Categories=Utility;" "Categories=AudioVideo;Audio;Player;" \
              --replace-fail "Exec=/opt/dev.krtirtho.spotube/dev.krtirtho.spotube" "Exec=spotube"

            runHook postInstall
          '';

          # Replaces nixpkgs' GTK/webkitgtk set: this build draws through Skiko (X11 + GL).
          # The bundled JRE's own libraries are patched against these too.
          buildInputs = with final; [
            alsa-lib
            fontconfig
            freetype
            gtk3
            libGL
            libX11
            libxkbcommon
            xorg.libXext
            xorg.libXi
            xorg.libXrender
            xorg.libXtst
            zlib
          ];

          # Playback is vlcj, not mpv, and it dlopen()s libvlc by soname through JNA — so
          # libvlc has to be on LD_LIBRARY_PATH, and its plugin tree found explicitly.
          # `libvlc` rather than `vlc` keeps the Qt GUI out of the closure.
          # Nucleus extracts its natives (tao windowing, media control) from jars into
          # ~/.cache at runtime, so autoPatchelf never sees them; their linked and dlopen()ed
          # deps (GTK, EGL/GL, X11, Wayland) go here too.
          postFixup = ''
            makeWrapper $out/share/spotube/bin/dev.krtirtho.spotube $out/bin/spotube \
              --prefix LD_LIBRARY_PATH : ${
                lib.makeLibraryPath (
                  with final;
                  [
                    cairo
                    dbus
                    gdk-pixbuf
                    glib
                    gtk3
                    libGL
                    libvlc
                    libX11
                    stdenv.cc.cc.lib
                    wayland
                    xorg.libXext
                  ]
                )
              } \
              --set-default VLC_PLUGIN_PATH ${final.libvlc}/lib/vlc/plugins \
              --prefix PATH : ${lib.makeBinPath [ final.xdg-user-dirs ]}
          '';
        });
      }
    )
  ];
}
