{
  lib,
  pkgs,
}: let
  pname = "pilinara";
  version = "2.6.2";
in
  pkgs.stdenvNoCC.mkDerivation {
    inherit pname version;

    # Follow the AUR binary package layout; release tags and asset versions differ.
    src = pkgs.fetchurl {
      url = "https://github.com/Starfallan/PiliNara/releases/download/2.6.2/PiliNara_linux_2.2.0%2B6232_amd64.tar.gz";
      hash = "sha256-ArZLsDjMQ6zcLcTD05ZiAd6NfIfqnsnxaoBmGqbmAVQ=";
    };

    sourceRoot = ".";
    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      wrapGAppsHook3
      copyDesktopItems
    ];
    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
      gtk3
      libayatana-appindicator
      webkitgtk_4_1
      mpv-unwrapped
      libGL
    ];
    runtimeDependencies = map lib.getLib [pkgs.mpv-unwrapped pkgs.webkitgtk_4_1];

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 pilinara "$out/libexec/pilinara/pilinara"
      cp -a lib data "$out/libexec/pilinara/"
      # JNI is only used by Android; the Linux bundle never loads it.
      rm "$out/libexec/pilinara/lib/libdartjni.so"
      mkdir -p "$out/bin"
      ln -s "$out/libexec/pilinara/pilinara" "$out/bin/pilinara"
      install -Dm644 data/flutter_assets/assets/images/logo/logo.png \
        "$out/share/icons/hicolor/512x512/apps/pilinara.png"

      runHook postInstall
    '';

    preFixup = ''
      gappsWrapperArgs+=(
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [pkgs.mpv-unwrapped pkgs.webkitgtk_4_1]}:$out/libexec/pilinara/lib"
      )
    '';

    desktopItems = [
      (pkgs.makeDesktopItem {
        name = "com.example.pilinara";
        desktopName = "PiliNara";
        comment = "Third-party Bilibili client developed in Flutter";
        exec = "pilinara %u";
        icon = "pilinara";
        startupWMClass = "com.example.pilinara";
        categories = ["Video" "AudioVideo" "Player"];
        mimeTypes = ["x-scheme-handler/bilibili"];
      })
    ];

    passthru.updateScript = pkgs.callPackage ../../lib/update-script.nix {
      script = "update-pilinara.sh";
    };

    meta = {
      description = "PiliPlus fork with additional Bilibili client features";
      homepage = "https://github.com/Starfallan/PiliNara";
      changelog = "https://github.com/Starfallan/PiliNara/releases/tag/${version}";
      license = lib.licenses.gpl3Plus;
      mainProgram = "pilinara";
      platforms = ["x86_64-linux"];
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
