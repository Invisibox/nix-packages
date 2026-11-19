{
  lib,
  pkgs,
}: let
  pname = "shotori";
  version = "0.19.1";
in
  pkgs.stdenvNoCC.mkDerivation {
    inherit pname version;

    src = pkgs.fetchurl {
      url = "https://github.com/shotori-screenshot/shotori/releases/download/v${version}/shotori-v${version}-x86_64.tar.gz";
      hash = "sha256-J2gn3p+suKxK43ELAQNOSXP7dQmGQ40o3dTSQg6iOvQ=";
    };

    nativeBuildInputs = with pkgs; [autoPatchelfHook desktop-file-utils];
    buildInputs = with pkgs; [stdenv.cc.cc.lib libxcb libxkbcommon];
    # GPUI loads graphics and Wayland libraries at runtime.
    runtimeDependencies = with pkgs; [dbus.lib libglvnd vulkan-loader wayland];

    # The release tarball has no enclosing directory.
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    doInstallCheck = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 shotori "$out/bin/shotori"
      install -Dm644 LICENSE "$out/share/licenses/shotori/LICENSE"
      install -Dm644 assets/shotori.desktop "$out/share/applications/shotori.desktop"
      install -Dm644 assets/app/shotori.svg "$out/share/icons/hicolor/scalable/apps/shotori.svg"
      for icon in assets/app/shotori-*.png; do
        size=''${icon##*/shotori-}
        size=''${size%.png}
        install -Dm644 "$icon" "$out/share/icons/hicolor/''${size}x''${size}/apps/shotori.png"
      done
      runHook postInstall
    '';

    installCheckPhase = ''
      runHook preInstallCheck
      desktop-file-validate "$out/share/applications/shotori.desktop"
      actualVersion=$("$out/bin/shotori" --version)
      echo "$actualVersion"
      test "$actualVersion" = "shotori ${version}"
      runHook postInstallCheck
    '';

    passthru.updateScript = pkgs.callPackage ../../lib/update-script.nix {
      script = "update-shotori.sh";
    };

    meta = {
      description = "Wayland screenshot tool with annotations, pinning, scrolling capture and OCR";
      homepage = "https://github.com/shotori-screenshot/shotori";
      changelog = "https://github.com/shotori-screenshot/shotori/releases/tag/v${version}";
      license = lib.licenses.mit;
      mainProgram = "shotori";
      platforms = ["x86_64-linux"];
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
