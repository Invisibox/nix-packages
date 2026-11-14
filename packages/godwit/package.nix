{
  lib,
  pkgs,
}: let
  pname = "godwit";
  version = "1.36.0";

  runtimeLibs = with pkgs; [
    at-spi2-core
    cairo
    fontconfig
    gdk-pixbuf
    glib
    gtk-layer-shell
    gtk3
    harfbuzz
    libayatana-appindicator
    libdbusmenu-gtk3
    libepoxy
    libGL
    libsecret
    libsoup_3
    libx11
    pango
    wayland
    webkitgtk_4_1
  ];
in
  pkgs.stdenvNoCC.mkDerivation {
    inherit pname version;

    src = pkgs.fetchurl {
      url = "https://dl.godwit.email/godwit_${version}_amd64.deb";
      hash = "sha256-kydFBh6zBAHi92E5Cgcm+3VOMg2ULSSn5PUQyQ9pnl0=";
    };

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      dpkg
      desktop-file-utils
      makeWrapper
      wrapGAppsHook3
    ];
    buildInputs =
      runtimeLibs
      ++ (with pkgs; [
        adwaita-icon-theme
        glib-networking
        gsettings-desktop-schemas
        stdenv.cc.cc.lib
      ]);

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    dontWrapGApps = true;
    doInstallCheck = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x "$src" .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin"
      cp -a opt "$out/"
      cp -a usr/share "$out/"

      substituteInPlace "$out/share/applications/godwit.desktop" \
        --replace-fail 'Exec=/opt/godwit/godwit' "Exec=$out/bin/godwit"

      runHook postInstall
    '';

    postFixup = ''
      # MyGo loads the UI libraries through purego/dlopen.
      makeWrapper "$out/opt/godwit/godwit" "$out/bin/godwit" \
        "''${gappsWrapperArgs[@]}" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}" \
        --prefix PATH : ${lib.makeBinPath [pkgs.xdg-utils]}
    '';

    installCheckPhase = ''
      runHook preInstallCheck
      desktop-file-validate "$out/share/applications/godwit.desktop"
      actualVersion=$("$out/bin/godwit" --version)
      echo "$actualVersion"
      test "$actualVersion" = "godwit ${version}"
      runHook postInstallCheck
    '';

    passthru.updateScript = pkgs.callPackage ../../lib/update-script.nix {
      script = "update-godwit.sh";
    };

    meta = {
      description = "Open-source, AI-native email client";
      homepage = "https://github.com/godwit-email/godwit";
      changelog = "https://github.com/godwit-email/godwit/releases/tag/v${version}";
      license = lib.licenses.asl20;
      mainProgram = "godwit";
      platforms = ["x86_64-linux"];
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
