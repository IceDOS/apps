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

          # Replaces nixpkgs' GTK/webkitgtk set: Skiko draws (X11 + GL), but the bundled
          # WebKitGTK webview (plugin login) keeps webkitgtk_4_1 and libsoup_3; the JRE uses them too.
          buildInputs = with final; [
            alsa-lib
            fontconfig
            freetype
            glib-networking
            gtk3
            libGL
            libsoup_3
            libX11
            libxkbcommon
            webkitgtk_4_1
            libxext
            libxi
            libxrender
            libxtst
            zlib
          ];

          # vlcj dlopen()s libvlc by soname through JNA, so libvlc and its plugin tree join
          # LD_LIBRARY_PATH (`libvlc`, not `vlc`, keeps the Qt GUI out of the closure).

          # Nucleus extracts its natives (tao windowing, media, the GTK webview) into ~/.cache
          # at runtime, so autoPatchelf misses them; their linked/dlopen()ed deps go here too.

          # WebKitGTK uses libsoup3, whose GIO TLS module comes from glib-networking (blank
          # login webview otherwise); --prefix keeps the session's GIO_EXTRA_MODULES (gvfs, dconf).

          # $out/bin/spotube is the launcher the overlay installs (Exec=spotube in the .desktop);
          # makeWrapper writes it directly and folds every flag below into it.
          postFixup = ''
            makeWrapper $out/share/spotube/bin/dev.krtirtho.spotube $out/bin/spotube \
              --prefix GIO_EXTRA_MODULES : ${final.glib-networking}/lib/gio/modules \
              --set-default SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt \
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
                    libsoup_3
                    libvlc
                    libX11
                    stdenv.cc.cc.lib
                    wayland
                    webkitgtk_4_1
                    libxext
                  ]
                )
              } \
              --set-default VLC_PLUGIN_PATH ${final.libvlc}/lib/vlc/plugins \
              --prefix PATH : ${
                lib.makeBinPath [
                  final.python3
                  final.xdg-user-dirs
                ]
              }
          '';

        });
      }
    )
  ];
}
