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
            # nixpkgs' hook still names the old dear_imgui submodule; upstream renamed
            # it to externals/imgui, so rewrite the token to track the current pin.
            postCheckout = lib.replaceString "dear_imgui" "imgui" old.src.postCheckout + ''
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

          cmakeFlags = (old.cmakeFlags or [ ]) ++ [
            (lib.cmakeBool "ENABLE_SYSTEM_LIBRARIES" true)
          ];

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
