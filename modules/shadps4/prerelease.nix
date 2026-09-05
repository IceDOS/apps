{
  nixpkgs.overlays = [
    (
      final: super:

      let
        inherit (super) lib;
        source = builtins.fromJSON (builtins.readFile ./prerelease.json);
      in

      assert lib.assertMsg (source.rev != "" && source.hash != "") ''
        shadps4: prerelease.json holds no pin yet. Run modules/shadps4/update.sh, or let
        the update-shadps4 workflow run, before enabling
        icedos.applications.shadps4.prerelease.
      '';

      {
        shadps4 = super.shadps4.overrideAttrs (old: {
          version = source.version;

          # The pin already merged PR #4786, so the patch applies reversed.
          patches = builtins.filter (p: p.name != "use-system-zarchive.patch") (old.patches or [ ]);

          src = final.fetchFromGitHub {
            owner = "shadps4-emu";
            repo = "shadPS4";

            inherit (source) rev hash;

            # Passing postCheckout is what picks fetchgit over fetchzip; drop it and src
            # becomes a tarball with an empty externals/, no COMMIT, and a stale hash.
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

          # abseil-cpp stays an uninitialised submodule, so the block would add_subdirectory
          # an empty dir. grep because a sed range matching nothing still exits 0.
          postPatch = old.postPatch + ''
            grep -q '^if (NOT TARGET absl::strings)' externals/CMakeLists.txt
            sed -i '/^if (NOT TARGET absl::strings)/,/^endif()/d' externals/CMakeLists.txt
          '';

          cmakeFlags = (old.cmakeFlags or [ ]) ++ [
            (lib.cmakeBool "ENABLE_SYSTEM_LIBRARIES" true)
          ];

          # protobuf_LOCAL_DEPENDENCIES_ONLY kills its FetchContent fallback, so
          # find_package(absl) must hit — with clang, or the Cord symbols mangle wrong.
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
