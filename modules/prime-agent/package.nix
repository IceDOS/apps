{
  lib,
  stdenv,
  buildNpmPackage,
  mcpCallTimeout ? 900,
  fetchFromGitHub,
  autoPatchelfHook,
  bash,
  cacert,
  fd,
  git,
  gnutar,
  makeWrapper,
  nodejs,
  npm-lockfile-fix,
  python311,
  ripgrep,
  uv,
  versionCheckHook,
  xdg-utils,
}:

let
  # Pin refreshed by ./update.sh; `rev` is tracked separately from `version` so an
  # upstream tag-prefix change does not need a package edit.
  source = builtins.fromJSON (builtins.readFile ./source.json);

  runtimePath = [
    nodejs
    bash
    fd
    git
    ripgrep
    gnutar
    uv
    python311
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ xdg-utils ];
in
buildNpmPackage (finalAttrs: {
  pname = "prime-agent";
  inherit (source) version;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "PrimeIntellect-ai";
    repo = "prime-agent";
    tag = "v${finalAttrs.version}";
    inherit (source) hash;

    # The upstream lockfile omits registry metadata for workspace dependencies.
    postFetch = ''
      ${lib.optionalString stdenv.hostPlatform.isDarwin "export REQUESTS_CA_BUNDLE=${cacert}/etc/ssl/certs/ca-bundle.crt"}
      ${lib.getExe npm-lockfile-fix} $out/package-lock.json
    '';
  };

  patches = [
    # MCP tool-call timeout defaults to 60s — too short for heavy reviews.
    # Make it configurable via PRIME_AGENT_MCP_CALL_TIMEOUT (seconds).
    ./patches/mcp-call-timeout-env.patch

    # modelOverrides is only applied to built-in models; custom models from
    # models[] overwrite them, ignoring overrides like contextWindow.
    ./patches/model-registry-model-overrides.patch

    # bootstrap.ts runs `uv python install 3.11` before creating the venv, downloading
    # a Python that UV_PYTHON_PREFERENCE=system never uses. Drop the redundant fetch.
    ./patches/remove-uv-python-install.patch

    # daemon writes its ownership registry to hardcoded ~/.prime; its env override is
    # stripped on launch. Follow PRIME_AGENT_CODING_AGENT_DIR instead so nothing lives there.
    ./patches/daemon-supervisor-registry-follow-agentdir.patch
  ];

  npmDepsFetcherVersion = 2;
  inherit (source) npmDepsHash;

  # Install scripts would download or build native addons (koffi, esbuild, ...);
  # runtime addons ship prebuilts or are Linux-unused (koffi), so skip them.
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ makeWrapper ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  # @mariozechner/clipboard's napi addon links libgcc_s; autoPatchelfHook must
  # find it (also in the LD_LIBRARY_PATH of the wrapper below).
  buildInputs = [ stdenv.cc.cc.lib ];

  dontConfigure = true;
  # Build the workspace packages explicitly because the root package is not the CLI.
  dontNpmBuild = true;
  buildPhase = ''
    runHook preBuild

    export PATH="$PWD/node_modules/.bin:$PATH"
    npm --workspace packages/tui run build
    (cd packages/ai && tsgo -p tsconfig.build.json)
    npm --workspace packages/agent run build
    npm --workspace packages/coding-agent run build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    npm prune --omit=dev --ignore-scripts
    packageDir=$out/lib/prime-agent
    mkdir -p "$packageDir" $out/bin
    cp -R node_modules "$packageDir/node_modules"
    rm -rf "$packageDir/node_modules/koffi"
    cp packages/coding-agent/package.json "$packageDir/package.json"
    cp -R packages/coding-agent/dist "$packageDir/dist"
    for path in README.md CHANGELOG.md docs examples skills; do
      cp -R "packages/coding-agent/$path" "$packageDir/$path"
    done

    mkdir -p "$packageDir/packages"
    for workspace in ai agent tui coding-agent; do
      mkdir -p "$packageDir/packages/$workspace"
      cp "packages/$workspace/package.json" "$packageDir/packages/$workspace/package.json"
      cp -R "packages/$workspace/dist" "$packageDir/packages/$workspace/dist"
    done
    for path in docs examples skills; do
      cp -R "packages/coding-agent/$path" "$packageDir/packages/coding-agent/$path"
    done

    # The venv uses nix's Python; UV_PYTHON_DOWNLOADS=manual stops surprise downloads.
    makeWrapper ${lib.getExe nodejs} $out/bin/prime-agent \
      --add-flags "$packageDir/dist/bundle/cli.js" \
      --set PI_PACKAGE_DIR "$packageDir" \
      --set PI_SKIP_VERSION_CHECK 1 \
      --set UV_PYTHON_PREFERENCE system \
      --set UV_PYTHON_DOWNLOADS manual \
      --set-default PRIME_AGENT_MCP_CALL_TIMEOUT ${toString mcpCallTimeout} \
      --prefix PATH : ${lib.makeBinPath runtimePath} \
      ${lib.optionalString stdenv.hostPlatform.isLinux "--prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [ stdenv.cc.cc.lib ]
      }"}

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";

  installCheckPhase = ''
    runHook preInstallCheck

    requiredPythonVersion=$(grep -oP 'PYTHON_VERSION = "\K[^"]+' \
      packages/coding-agent/src/core/kernel/bootstrap.ts)
    actualVersion=$(${lib.getExe python311} -c 'import sys;print("%d.%d"%sys.version_info[:2])')
    if [ "$actualVersion" != "$requiredPythonVersion" ]; then
      echo "ERROR: prime-agent requires Python $requiredPythonVersion but $actualVersion provided"
      exit 1
    fi

    runHook postInstallCheck
  '';

  meta = {
    description = "Self-improving RLM coding and research agent";
    homepage = "https://github.com/PrimeIntellect-ai/prime-agent";
    changelog = "https://github.com/PrimeIntellect-ai/prime-agent/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.okwilkins ];
    mainProgram = "prime-agent";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
      "aarch64-darwin"
    ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
})
