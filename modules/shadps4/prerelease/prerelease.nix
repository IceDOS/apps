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

            # GitHub throttles unauthenticated git clones by TLS fingerprint (JA4) and
            # answers the blocked ones with 401 + x-github-edge-protection:
            # ja4-campaign-git-error, which git reports as "could not read Username".
            # HTTP/1.1 has a different fingerprint and is not blocked. Env rather than
            # `git config`, so it covers the git calls baked into old.src.postCheckout
            # too, and no git config file is written into the read-only sandbox HOME.
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
            + lib.replaceString "dear_imgui" "\"$imgui\"" old.src.postCheckout
            + ''
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

            # These call std::mem* but include neither <cstring> nor <string.h>; they only
            # compile when some other header drags the declarations in. Keyed on the call
            # so this turns into a no-op once upstream adds the include itself.
            for f in src/video_core/amdgpu/regs.cpp src/video_core/amdgpu/resource.h; do
              if grep -qE 'std::(memset|memcpy|memcmp|memmove)' "$f" &&
                 ! grep -qE '^#include <cstring>' "$f"; then
                sed -i '0,/^#include /s//#include <cstring>\n\n#include /' "$f"
              fi
            done
          '';

          cmakeFlags = (old.cmakeFlags or [ ]) ++ [
            (lib.cmakeBool "ENABLE_SYSTEM_LIBRARIES" true)
          ];

          # elf.cpp includes <fmt/core.h> and calls fmt::format. Upstream's bundled
          # ext-fmt makes core.h pull in format.h, but system fmt 12 gates that behind
          # FMT_DEPRECATED_HEAVY_CORE, so the system build fails with "no member named
          # 'format' in namespace 'fmt'".
          NIX_CFLAGS_COMPILE = (old.NIX_CFLAGS_COMPILE or "") + " -DFMT_DEPRECATED_HEAVY_CORE";

          # Upstream forces ENABLE_GLSLANG_BINARIES on to compile host shaders, and
          # glslang's standalone build needs a Python 3 interpreter.
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.python3 ];

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
