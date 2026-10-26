{
  lib,
  pkgs,
}: let
  pname = "oxideterm";
  version = "2.2.6";

  src = pkgs.fetchurl {
    url = "https://github.com/AnalyseDeCircuit/oxideterm/releases/download/v${version}/OxideTerm_${version}_linux_x64.deb";
    hash = "sha256-TggnEPxJDSyXQTffS31TPeUndp6g2B0U/dCSKPeFAGI=";
  };

  oxideTermPackage = pkgs.stdenv.mkDerivation {
    inherit pname version src;

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.dpkg
      pkgs.wrapGAppsHook3
    ];

    buildInputs = with pkgs; [
      alsa-lib
      cairo
      dbus
      gdk-pixbuf
      glib
      glib-networking
      gtk3
      libsoup_3
      wayland
      webkitgtk_4_1
      vulkan-loader
    ];

    dontConfigure = true;
    dontBuild = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x "$src" .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin"
      cp -R opt "$out/"
      cp -R usr/* "$out/"

      appDir="$out/opt/oxideterm"
      cli="$appDir/resources/cli-bin/x86_64-unknown-linux-gnu/oxideterm"

      chmod +x "$appDir/oxideterm-native"
      chmod +x "$cli"
      chmod +x "$appDir/resources/agents/"*

      ln -s "$cli" "$out/bin/oxideterm"
      ln -s "$appDir/oxideterm-native" "$out/bin/oxideterm-native"

      substituteInPlace "$out/share/applications/com.oxideterm.app.desktop" \
        --replace-fail "/opt/oxideterm/oxideterm-native" "oxideterm-native"

      runHook postInstall
    '';

    preFixup = ''
      gappsWrapperArgs+=(
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [
        pkgs.wayland
        pkgs.vulkan-loader
      ]}
        --set-default OXIDETERM_LINUX_WEBVIEW_PROFILE safe
        --set-default WEBKIT_DISABLE_DMABUF_RENDERER 1
        --set-default WEBKIT_DISABLE_COMPOSITING_MODE 1
      )
    '';

    meta = {
      description = "Modern SSH terminal client built with Rust and Tauri";
      homepage = "https://github.com/AnalyseDeCircuit/oxideterm";
      license = lib.licenses.gpl3Only;
      mainProgram = "oxideterm-native";
      platforms = ["x86_64-linux"];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  };
in
  oxideTermPackage
