{
  lib,
  pkgs,
}: let
  pname = "pebble-mail";
  version = "0.1.6";
in
  pkgs.stdenvNoCC.mkDerivation {
    inherit pname version;

    src = pkgs.fetchurl {
      url = "https://github.com/QingJ01/Pebble/releases/download/v${version}/Pebble_${version}_amd64.deb";
      hash = "sha256-gegLXbFCdO7IyFXrf+mCOG4QImKeDfs+MNsm4cJKb5U=";
    };

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      desktop-file-utils
      dpkg
      wrapGAppsHook3
    ];

    buildInputs =
      (with pkgs; [
        adwaita-icon-theme
        cairo
        dbus
        fontconfig
        freetype
        gdk-pixbuf
        glib
        glib-networking
        gsettings-desktop-schemas
        gtk3
        harfbuzz
        libayatana-appindicator
        libGL
        libsoup_3
        openssl
        pango
        stdenv.cc.cc.lib
        webkitgtk_4_1
      ])
      ++ (with pkgs.gst_all_1; [
        gstreamer
        gst-plugins-base
        gst-plugins-good
        gst-plugins-bad
      ]);

    dontConfigure = true;
    dontBuild = true;
    doInstallCheck = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x "$src" .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -a usr/bin usr/share "$out/"
      runHook postInstall
    '';

    preFixup = ''
      # The tray library is loaded through dlopen; GTK wrapping handles TLS and GStreamer.
      gappsWrapperArgs+=(
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [pkgs.libayatana-appindicator]}
        --prefix PATH : ${lib.makeBinPath [pkgs.xdg-utils]}
      )
    '';

    installCheckPhase = ''
      runHook preInstallCheck
      desktop-file-validate "$out/share/applications/Pebble.desktop"
      runHook postInstallCheck
    '';

    passthru.updateScript = pkgs.callPackage ../../lib/update-script.nix {
      script = "update-pebble-mail.sh";
    };

    meta = {
      description = "Local-first desktop email client built with Rust, Tauri, and React";
      homepage = "https://github.com/QingJ01/Pebble";
      changelog = "https://github.com/QingJ01/Pebble/releases/tag/v${version}";
      license = lib.licenses.agpl3Only;
      mainProgram = "pebble";
      platforms = ["x86_64-linux"];
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
