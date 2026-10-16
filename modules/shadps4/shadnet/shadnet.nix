{
  nixpkgs.overlays = [
    (
      final: super:

      let
        inherit (super) lib;
        source = builtins.fromJSON (builtins.readFile ./shadnet.json);
      in

      assert lib.assertMsg (source.rev != "" && source.hash != "") ''
        shadps4: shadnet.json holds no pin yet. Run the shadp2p updater, or let the
        update-shadps4 workflow run, before enabling
        icedos.applications.shadps4.shadnet.
      '';

      {
        # shadp2p = shadPS4 fork with the shadnet P2P client. This overlay is only
        # routed when prerelease is disabled, so `super.shadps4` is plain nixpkgs
        # here; only one composed shadps4 binary results.
        shadps4 = super.shadps4.overrideAttrs (old: {
          version = source.version;

          patches = builtins.filter (p: p.name != "use-system-zarchive.patch") (old.patches or [ ]);

          src = final.fetchFromGitHub {
            owner = "Wozzardman";
            repo = "shadp2p";

            inherit (source) rev hash;

            # postCheckout picks fetchgit over fetchzip; without it src is a tarball
            # with an empty externals/ and a stale hash.
            # imgui is dear_imgui until the fork rebases past upstream's rename.
            # HTTP/1.1 dodges GitHub's JA4 throttle, which answers with 401 and fails
            # the clone. Same reason and same env form as prerelease/prerelease.nix.
            postCheckout = ''
              export GIT_CONFIG_COUNT=1
              export GIT_CONFIG_KEY_0=http.version
              export GIT_CONFIG_VALUE_0=HTTP/1.1
            ''
            + ''
              if grep -qE '^[[:space:]]*path[[:space:]]*=[[:space:]]*externals/imgui[[:space:]]*$' "$out/.gitmodules"; then
                imgui=imgui
              else
                imgui=dear_imgui
              fi
            ''
            # Local copy of nixpkgs' 0.18 checkout; same reason as prerelease/prerelease.nix.
            + ''
              git -C "$out" rev-parse --short=8 HEAD > $out/COMMIT
              date -u -d "@$(git -C "$out" log -1 --pretty=%ct)" "+%Y-%m-%dT%H:%M:%SZ" > $out/SOURCE_DATE_EPOCH

              git -C "$out/externals" submodule update --init --recursive \
                glslang \
                zydis \
                sirit \
                tracy \
                libusb \
                discord-rpc \
                hwinfo \
                openal-soft \
                "$imgui" \
                LibAtrac9 \
                aacdec/fdk-aac \
                spdlog \
                libressl \
                ImGuiFileDialog \
                protobuf

              git -C "$out/externals" submodule update --init --recursive \
                cpp-httplib \
                protobuf \
                zarchive \
                zstd
            '';
          };

          # abseil-cpp stays an uninitialised submodule; drop its block so
          # find_package(absl) resolves against the system abseil added below.
          # Idempotent so it also works when chained on a prerelease base.
          postPatch = old.postPatch + ''
            if grep -q '^if (NOT TARGET absl::strings)' externals/CMakeLists.txt; then
              sed -i '/^if (NOT TARGET absl::strings)/,/^endif()/d' externals/CMakeLists.txt
            fi
          '';

          # The fork's protobuf still FetchContent-downloads abseil. nixpkgs 0.19 dropped
          # this source-dir override, so keep the one 0.18 passed.
          cmakeFlags = (old.cmakeFlags or [ ]) ++ [
            (lib.cmakeBool "ENABLE_SYSTEM_LIBRARIES" true)
            (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_ABSL" "${final.fetchFromGitHub {
              owner = "abseil";
              repo = "abseil-cpp";
              tag = "20250512.1";
              hash = "sha256-eB7OqTO9Vwts9nYQ/Mdq0Ds4T1KgmmpYdzU09VPWOhk=";
            }}")
          ];

          # elf.cpp includes <fmt/core.h> and calls fmt::format. Upstream's bundled
          # ext-fmt makes core.h pull in format.h, but system fmt 12 gates that behind
          # FMT_DEPRECATED_HEAVY_CORE, so the system build fails with "no member named
          # 'format' in namespace 'fmt'".
          # nixpkgs sets env.NIX_CFLAGS_COMPILE; a top-level one would collide with it.
          env = (old.env or { }) // {
            NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -DFMT_DEPRECATED_HEAVY_CORE";
          };

          # protobuf_LOCAL_DEPENDENCIES_ONLY kills its FetchContent fallback, so
          # find_package(absl) must hit — with clang, or the Cord symbols mangle wrong.
          # Set seamless co-op on the binary itself: the fork's core reads
          # SHADPS4_BLOODBORNE_SEAMLESS_COOP via EnvFlagEnabled at runtime, so any
          # entry point (direct shadps4, qtlauncher, bb-launcher) gets it.
          postInstall = (old.postInstall or "") + ''
            wrapProgram $out/bin/shadps4 --set SHADPS4_BLOODBORNE_SEAMLESS_COOP 1
          '';

          buildInputs =
            old.buildInputs
            ++ (with final; [
              (abseil-cpp_202601.override { stdenv = clangStdenv; })
              freetype
              miniupnpc
            ]);
        });
      }
    )
  ];
}
