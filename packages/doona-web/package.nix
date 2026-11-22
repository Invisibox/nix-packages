# Adapted from ccicnce113424/nix-packages. See LICENSE.ccicnce113424.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpmBuildHook,
  pnpm_11,
  nodejs,
  callPackage,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "doona-web";
  version = "0.1.0-rc.6";

  src = fetchFromGitHub {
    owner = "Zakkaus";
    repo = "doona";
    tag = "v${finalAttrs.version}";
    hash = "sha256-5NRzRlVBbR9gFSZ0leNgnXdtPur0VMId36gKbXbWtQ0=";
  };

  __structuredAttrs = true;
  strictDeps = true;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = "sha256-N4Goi5+BddeW0C+NA+h0Ae2U9RWbVCmpliExQjySlUc=";
  };

  nativeBuildInputs = [pnpmConfigHook pnpmBuildHook pnpm_11 nodejs];
  pnpmBuildScript = "build";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r dist/. "$out/"
    rm -rf "$out/.vite"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -s "$out/index.html"
    runHook postInstallCheck
  '';

  passthru.updateScript = callPackage ../../lib/update-script.nix {
    script = "update-doona-web.sh";
  };

  meta = {
    description = "Web UI for the daeuniverse engines";
    homepage = "https://github.com/Zakkaus/doona";
    changelog = "https://github.com/Zakkaus/doona/releases/tag/v${finalAttrs.version}";
    license = with lib.licenses; [gpl3Only bsd0 asl20 bsd3 isc mit cc-by-30 cc-by-40 cc-by-sa-40 cc0 ofl];
    platforms = lib.platforms.linux;
  };
})
