{
  nixpkgs.overlays = [
    (
      final: super:

      let
        inherit (super) lib;
        source = builtins.fromJSON (builtins.readFile ./prerelease.json);
      in

      # An unseeded pin is committable — update.sh fills it on its next run — but it
      # would otherwise evaluate into a nameless derivation that only fails deep in the
      # build, so say so up front.
      assert lib.assertMsg (source.rev != "" && source.hash != "") ''
        shadps4: prerelease.json holds no pin yet. Run modules/shadps4/update.sh, or let
        the update-shadps4 workflow run, before enabling
        icedos.applications.shadps4.prerelease.
      '';

      {
        shadps4 = super.shadps4.overrideAttrs (old: {
          version = source.version;

          src = final.fetchFromGitHub {
            owner = "shadps4-emu";
            repo = "shadPS4";

            inherit (source) rev hash;

            # nixpkgs' hook (submodule init plus the COMMIT/SOURCE_DATE_EPOCH files its
            # postPatch reads), followed by the two submodules the prerelease newly
            # needs: protobuf is an unguarded add_subdirectory in externals, and
            # np_handler.cpp includes <httplib.h> unconditionally.
            postCheckout = old.src.postCheckout + ''

              git -C externals submodule update --init --recursive \
                cpp-httplib \
                protobuf
            '';
          };

          # shadPS4 forces protobuf to FetchContent abseil from GitHub, which the build
          # sandbox has no network for. `CACHE INTERNAL` implies FORCE, so a -D flag
          # cannot override it — flip it in the source and let protobuf find nixpkgs'
          # abseil instead.
          postPatch = old.postPatch + ''
            substituteInPlace externals/CMakeLists.txt \
              --replace-fail 'set(protobuf_FORCE_FETCH_DEPENDENCIES ON  CACHE INTERNAL "")' \
                             'set(protobuf_FORCE_FETCH_DEPENDENCIES OFF CACHE INTERNAL "")'
          '';

          # Every find_package moved behind this option after v0.16.0 and it defaults
          # off; without it spdlog fetches fmt over the network and the uninitialised
          # externals/ submodules are used in place of the nixpkgs dependencies.
          cmakeFlags = (old.cmakeFlags or [ ]) ++ [
            (lib.cmakeBool "ENABLE_SYSTEM_LIBRARIES" true)
          ];

          # find_package targets nixpkgs' shadps4 does not already supply. Each one
          # falls back to an uninitialised submodule directory when missing.
          #
          # abseil must be built with clang like shadps4 itself: clang mangles a
          # dependent non-type template parameter with a `Tn<type>` prefix and gcc does
          # not, so the stock gcc-built library is missing the exact Cord symbols the
          # in-tree protobuf emits calls to. `abseil-cpp` is an alias whose only
          # argument is the LTS package, so the stdenv swap goes through that.
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
