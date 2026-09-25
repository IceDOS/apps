{
  nixpkgs.overlays = [
    (
      final: prev:

      let
        inherit (prev) lib;
        source = lib.importJSON ./git.json;

        # Upstream builds with Temurin 21; jpackage and jlink come from this JDK too.
        jdk = final.temurin-bin-21;
        # AGP 8 needs the wrapper's gradle; 9.6+ removed an internal API it uses.
        gradle =
          (final.gradle-packages.mkGradle {
            inherit (source.gradle) version hash;
            defaultJava = jdk;
          }).wrapped;

        # AGP needs an SDK to configure :composeApp even though only desktop tasks run, and
        # gobley reads the NDK path while configuring its Android tasks. The NDK is AGP 8's default.
        androidSdk =
          ((final.androidenv.override { licenseAccepted = true; }).composeAndroidPackages {
            platformVersions = [ source.androidPlatform ];
            includeEmulator = false;
            includeSystemImages = false;
            includeNDK = true;
            ndkVersions = [ "27.0.12077973" ];
          }).androidsdk;

        fetchSpotubeRepo =
          repo: pin:
          final.fetchFromGitHub {
            owner = "team-spotube";
            inherit repo;
            inherit (pin) rev hash;
          };

        # gobley `cargo install`s its bindgen from crates.io at build time; this prebuilt copy
        # stands in for it (see the cargo shim below).
        uniffiBindgen = final.rustPlatform.buildRustPackage {
          pname = "gobley-uniffi-bindgen";
          inherit (source.uniffiBindgen) version cargoHash;

          src = final.fetchCrate {
            pname = "gobley-uniffi-bindgen";
            inherit (source.uniffiBindgen) version hash;
          };

          doCheck = false;
        };

        # gobley calls `rustup target add`, reads the version of the rustc next to it, and
        # installs its bindgen through `cargo install`. The toolchain here is nixpkgs' host
        # rust, so rustup is a no-op and `cargo install` copies the prebuilt bindgen.
        # gobley's version regex allows one "(...)" suffix; nixpkgs' rustc prints two.
        rustShims = final.runCommand "spotube-rust-shims" { } ''
          mkdir -p $out/bin

          cat > $out/bin/rustc <<'EOF'
          #!${final.runtimeShell}
          if [ "$*" = --version ]; then
            ${final.rustc}/bin/rustc --version | cut -d' ' -f1,2
            exit 0
          fi
          exec ${final.rustc}/bin/rustc "$@"
          EOF

          cat > $out/bin/rustup <<'EOF'
          #!${final.runtimeShell}
          exit 0
          EOF

          cat > $out/bin/cargo <<'EOF'
          #!${final.runtimeShell}
          if [ "$1" = install ]; then
            while [ $# -gt 0 ]; do
              [ "$1" = --root ] && root="$2"
              shift
            done
            mkdir -p "$root/bin"
            cp ${uniffiBindgen}/bin/gobley-uniffi-bindgen "$root/bin/"
            exit 0
          fi
          exec ${final.cargo}/bin/cargo "$@"
          EOF

          chmod +x $out/bin/*
        '';

        gradlePlugin = fetchSpotubeRepo "gradle-plugin" source.gradlePlugin;
        vlcjBundler = fetchSpotubeRepo "vlcj-bundler-gradle-plugin" source.vlcjBundler;

        # Upstream's deb step runs electron-builder through npx, which needs npm at build
        # time. This stops at the app image and lays out the same tree the deb holds, so the
        # nightly repackage installs it unchanged.
        tree = final.stdenv.mkDerivation (finalAttrs: {
          pname = "spotube-git-tree";
          inherit (source) version;

          src = fetchSpotubeRepo "spotube" source;

          cargoRoot = "composeApp";
          cargoDeps = final.rustPlatform.fetchCargoVendor {
            inherit (finalAttrs) src;
            sourceRoot = "${finalAttrs.src.name}/composeApp";
            hash = source.cargoHash;
          };

          nativeBuildInputs = [
            gradle
            jdk
            final.imagemagick
            final.rustPlatform.cargoSetupHook
            final.rustc
          ];

          mitmCache = gradle.fetchDeps {
            pkg = finalAttrs.finalPackage;
            data = ./git-deps.json;
          };

          # The daemon JVM criteria ask gradle to download a Temurin build, which is not
          # possible offline. Bindings come from the host library instead of Android's, so
          # no Android rust target is needed. The plugin template project fails to configure
          # offline, and the app never uses it.
          postPatch = ''
            rm gradle/gradle-daemon-jvm.properties
            substituteInPlace settings.gradle.kts --replace-fail 'include(":js_plugin_example")' ""

            cat >> composeApp/build.gradle.kts <<'EOF'

            uniffi {
                generateFromLibrary {
                    build = GobleyHost.current.rustTarget
                    variant = gobley.gradle.Variant.Release
                }
            }
            EOF

            echo "sdk.dir=${androidSdk}/libexec/android-sdk" > local.properties
          '';

          gradleBuildTask = ":composeApp:createReleaseDistributable";
          gradleUpdateTask = finalAttrs.gradleBuildTask;
          gradleFlags = [ "--stacktrace" ];

          # Upstream CI publishes these unreleased gradle plugins to mavenLocal before
          # building the app; this does the same inside the build.
          preBuild = ''
            export ANDROID_HOME=${androidSdk}/libexec/android-sdk
            export PATH=${rustShims}/bin:$PATH
            # gobley looks for the toolchain in ~/.cargo/bin, not on PATH.
            export HOME="$NIX_BUILD_TOP/home"
            mkdir -p "$HOME/.cargo"
            ln -sfn ${rustShims}/bin "$HOME/.cargo/bin"

            gradleFlagsArray+=(-Dmaven.repo.local="$NIX_BUILD_TOP/m2")
            for plugin in gradle-plugin:${gradlePlugin} vlcj-bundler:${vlcjBundler}; do
              dir="$NIX_BUILD_TOP/''${plugin%%:*}"
              cp -r "''${plugin#*:}" "$dir"
              chmod -R u+w "$dir"
              (cd "$dir" && gradle publishToMavenLocal)
            done
          '';

          # Same desktop entry the deb ships, which the repackage rewrites. Upstream's deb
          # icon is Nucleus' default Kotlin logo, so the Spotube logo replaces it here.
          installPhase = ''
            runHook preInstall

            mkdir -p $out/opt $out/usr/share/applications
            cp -r composeApp/build/compose/binaries/main-release/app/dev.krtirtho.spotube $out/opt/

            cat > $out/usr/share/applications/dev.krtirtho.spotube.desktop <<'EOF'
            [Desktop Entry]
            Name=dev.krtirtho.spotube
            Exec=/opt/dev.krtirtho.spotube/dev.krtirtho.spotube %U
            Terminal=false
            Type=Application
            Icon=dev.krtirtho.spotube
            StartupWMClass=dev-krtirtho-spotube-MainKt
            Comment=Packaged desktop application
            Categories=Utility;
            EOF

            for size in 16 32 48 64 128 256 512; do
              dir=$out/usr/share/icons/hicolor/''${size}x''${size}/apps
              mkdir -p $dir
              magick assets/branding/spotube-logo.png -resize ''${size}x''${size} $dir/dev.krtirtho.spotube.png
            done

            runHook postInstall
          '';

          dontFixup = true;
        });
      in

      assert lib.assertMsg (source ? rev) ''
        spotube: git.json holds no pin yet. Run modules/spotube/update.sh git before
        enabling icedos.applications.spotube.git.
      '';

      {
        spotube = prev.spotube.overrideAttrs {
          inherit (source) version;
          src = tree;
          passthru = (prev.spotube.passthru or { }) // {
            inherit tree uniffiBindgen;
          };
        };
      }
    )
  ];
}
