# Adapted from ccicnce113424/nix-packages. See LICENSE.ccicnce113424.
{
  lib,
  stdenv,
  rustPlatform,
  rust,
  fetchFromGitHub,
  bpf-linker,
  llvmPackages_23,
  cmake,
  gitMinimal,
  iproute2,
  makeWrapper,
  ninja,
  symlinkJoin,
  versionCheckHook,
  aws-lc,
  pkg-config,
  sqlite,
  rust-jemalloc-sys,
  callPackage,
}: let
  rustPrebuilt = rust.packages.prebuilt;
  sysroot = symlinkJoin {
    name = "rustc-bootstrap-with-libsrc";
    paths = [rustPrebuilt.rustc-unwrapped];
    postBuild = ''
      mkdir -p "$out/lib/rustlib/src/rust"
      ln -s ${rustPlatform.rustLibSrc} "$out/lib/rustlib/src/rust/library"
    '';
  };
  rustcWithLibSrc = rustPrebuilt.rustc.override {inherit sysroot;};
  bpfLinker = bpf-linker.override {llvmPackagesForLinker = llvmPackages_23;};
in
  rustPlatform.buildRustPackage (finalAttrs: {
    pname = "honk-core";
    version = "0.1.0-beta.7";

    src = fetchFromGitHub {
      owner = "daeuniverse";
      repo = "honk";
      tag = "v${finalAttrs.version}";
      hash = "sha256-SDrsnFTFgwAVh1s7NpBQ0cLngQBdb0mZg2eNpMTf0oA=";
    };

    # The eBPF crate has its own Cargo.lock and builds outside the workspace.
    honk-ebpf = stdenv.mkDerivation (ebpfAttrs: {
      pname = "honk-ebpf";
      inherit (finalAttrs) version src;

      __structuredAttrs = true;
      strictDeps = true;
      dontStrip = true;
      dontPatchELF = true;
      noAuditTmpdir = true;

      cargoRoot = "crates/honk-ebpf";
      cargoDeps = rustPlatform.fetchCargoVendor {
        inherit (ebpfAttrs) pname version src cargoRoot;
        hash = "sha256-IQl1dBhyjAJ5a+ehuid4uJxoxKgrsQx3TtZ9wSYhr7o=";
      };

      nativeBuildInputs = [rustPlatform.cargoSetupHook bpfLinker rustcWithLibSrc rustPrebuilt.cargo];
      env.RUSTC_BOOTSTRAP = "1";

      postPatch = ''
        cp -a ${rustPlatform.rustVendorSrc}/. "$cargoDepsCopy/source-registry-0/"
      '';

      buildPhase = ''
        runHook preBuild
        pushd crates/honk-ebpf
        cargo build --offline --release -Zbuild-std=core --target bpfel-unknown-none
        popd
        runHook postBuild
      '';

      doCheck = true;
      checkPhase = ''
        runHook preCheck
        # Aya requires a BTF section when loading the object.
        readelf -SW crates/honk-ebpf/target/bpfel-unknown-none/release/honk-ebpf | grep -E '[[:space:]]\.BTF[[:space:]]'
        runHook postCheck
      '';

      installPhase = ''
        runHook preInstall
        install -Dm444 crates/honk-ebpf/target/bpfel-unknown-none/release/honk-ebpf "$out/honk-ebpf"
        runHook postInstall
      '';
    });

    cargoHash = "sha256-DzVEg+CUkbfq0i5oidq5VNc1InPC6Gf/Vqee2TJ2Um8=";

    __structuredAttrs = true;
    strictDeps = true;
    stripAllList = ["bin"];

    # Honk serves the separately packaged UI through native_api.ui.
    buildFeatures = ["honk-core/ebpf" "honk-core/native-api"];
    cargoBuildFlags = ["--package" "honk-core" "--package" "honk-tool"];

    nativeBuildInputs = [cmake gitMinimal makeWrapper ninja pkg-config rustPlatform.bindgenHook];
    buildInputs = [aws-lc sqlite rust-jemalloc-sys];

    # Ninja is used by boring-sys. Cargo still owns the outer build phases.
    dontUseNinjaBuild = true;
    dontUseNinjaCheck = true;
    dontUseNinjaInstall = true;
    env.CMAKE_GENERATOR = "Ninja";
    env.GITHUB_REF = "refs/tags/v${finalAttrs.version}";

    preBuild = ''
      # The embedding build script checks the object's stamp and freshness.
      objDir=crates/honk-ebpf/target/bpfel-unknown-none/release
      mkdir -p "$objDir"
      cp ${finalAttrs.honk-ebpf}/honk-ebpf "$objDir/honk-ebpf"
      channel=$(sed -n 's/^channel *= *"\(.*\)"/\1/p' crates/honk-ebpf/rust-toolchain.toml)
      printf %s "$channel" > "$objDir/honk-ebpf.toolchain"
      touch "$objDir/honk-ebpf" "$objDir/honk-ebpf.toolchain"
    '';

    postInstall = ''
      unit="$out/lib/systemd/system/honk-core.service"
      install -Dm644 install/honk-core.service "$unit"
      substituteInPlace "$unit" --replace-fail /usr/bin/honk-core "$out/bin/honk-core"
    '';

    postFixup = ''
      wrapProgram "$out/bin/honk-tool" --prefix PATH : ${lib.makeBinPath [iproute2]}
    '';

    # Upstream integration tests need eBPF, namespaces and live endpoints.
    doCheck = false;
    doInstallCheck = true;
    nativeInstallCheckInputs = [versionCheckHook];

    passthru = {
      inherit (finalAttrs) honk-ebpf;
      updateScript = callPackage ../../lib/update-script.nix {
        script = "update-honk-core.sh";
      };
    };

    meta = {
      description = "Linux transparent proxy with native and Clash APIs";
      homepage = "https://github.com/daeuniverse/honk";
      changelog = "https://github.com/daeuniverse/honk/releases/tag/v${finalAttrs.version}";
      license = lib.licenses.gpl3Only;
      mainProgram = "honk-core";
      platforms = lib.platforms.linux;
    };
  })
