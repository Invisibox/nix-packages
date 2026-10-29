{
  lib,
  pkgs,
}: let
  pname = "paseo-desktop";
  version = "0.14.0";

  deps = with pkgs; [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    gtk2
    dbus-glib
    libdbusmenu
    libappindicator-gtk3
    libdrm
    libGL
    libgbm
    libnotify
    libsecret
    libuuid
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxscrnsaver
    libxtst
    nspr
    nss
    pango
    pipewire
    udev
    vulkan-loader
    wayland
    zlib
  ];

  rpath = lib.makeLibraryPath deps + ":" + lib.makeSearchPathOutput "lib" "lib64" deps;

  xdgUtilsShim = pkgs.symlinkJoin {
    name = "paseo-xdg-utils";
    paths = [
      (pkgs.writeShellScriptBin "xdg-mime" ''
        if [ "''${1-}" = "default" ]; then
          case " $* " in
            *" x-scheme-handler/paseo "*) exit 0 ;;
          esac
        fi

        if [ "''${1-}" = "query" ] \
          && [ "''${2-}" = "default" ] \
          && [ "''${3-}" = "x-scheme-handler/paseo" ]; then
          echo "paseo-desktop.desktop"
          exit 0
        fi

        exec ${pkgs.xdg-utils}/bin/xdg-mime "$@"
      '')
      (pkgs.writeShellScriptBin "xdg-settings" ''
        if [ "''${1-}" = "set" ] \
          && [ "''${2-}" = "default-url-scheme-handler" ] \
          && [ "''${3-}" = "paseo" ]; then
          exit 0
        fi

        if [ "''${1-}" = "get" ] \
          && [ "''${2-}" = "default-url-scheme-handler" ] \
          && [ "''${3-}" = "paseo" ]; then
          echo "paseo-desktop.desktop"
          exit 0
        fi

        if [ "''${1-}" = "check" ] \
          && [ "''${2-}" = "default-url-scheme-handler" ] \
          && [ "''${3-}" = "paseo" ] \
          && [ "''${4-}" = "paseo-desktop.desktop" ]; then
          exit 0
        fi

        exec ${pkgs.xdg-utils}/bin/xdg-settings "$@"
      '')
    ];
  };

  src = pkgs.fetchurl {
    url = "https://github.com/getpaseo/paseo/releases/download/v${version}/Paseo-x86_64.AppImage";
    hash = "sha256-IL7xnEScuBVWs4XrB9qH2+8LvhfxV7Z8Ouxl3Ywtidg=";
  };

  package = pkgs.stdenv.mkDerivation {
    inherit pname version src;

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.imagemagick
      pkgs.squashfsTools
      (pkgs.buildPackages.wrapGAppsHook3.override {makeWrapper = pkgs.buildPackages.makeShellWrapper;})
    ];

    autoPatchelfIgnoreMissingDeps = ["libdbusmenu-gtk.so.4"];

    buildInputs =
      deps
      ++ (with pkgs; [
        adwaita-icon-theme
        gsettings-desktop-schemas
      ]);

    dontConfigure = true;
    dontBuild = true;

    unpackPhase = ''
      runHook preUnpack

      # Locate the squashfs image embedded in the AppImage and extract it.
      cp "$src" appimage
      chmod +w appimage
      offset=""
      for candidate in $(grep -abo hsqs appimage | cut -d: -f1); do
        if unsquashfs -s -o "$candidate" appimage >/dev/null 2>&1; then
          offset="$candidate"
          break
        fi
      done

      if [[ -z "$offset" ]]; then
        echo "unable to locate squashfs filesystem in AppImage" >&2
        exit 1
      fi

      unsquashfs -no-progress -d AppDir -o "$offset" appimage
      rm appimage

      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/lib" "$out/opt" "$out/share"
      cp -R AppDir/* "$out/opt/"

      icon_src="$out/opt/Paseo.png"
      for icon_size in 128 256 512; do
        install -d "$out/share/icons/hicolor/''${icon_size}x''${icon_size}/apps"
        magick "$icon_src" -resize "''${icon_size}x''${icon_size}" \
          "$out/share/icons/hicolor/''${icon_size}x''${icon_size}/apps/paseo-desktop.png"
      done

      makeWrapper "$out/opt/Paseo" "$out/bin/paseo-desktop" \
        --unset ELECTRON_RUN_AS_NODE \
        --prefix XDG_DATA_DIRS : ${pkgs.xdg-utils}/share \
        --prefix PATH : ${lib.makeBinPath [xdgUtilsShim pkgs.xdg-utils]}

      install -Dm644 "$out/opt/Paseo.desktop" "$out/share/applications/paseo-desktop.desktop"
      substituteInPlace "$out/share/applications/paseo-desktop.desktop" \
        --replace-fail "Exec=AppRun --class=Paseo %U" "Exec=paseo-desktop %U" \
        --replace-fail "Icon=Paseo" "Icon=paseo-desktop"

      runHook postInstall
    '';

    preFixup = ''
      gappsWrapperArgs+=(
        --prefix LD_LIBRARY_PATH : ${rpath}:$out/opt:$out/lib
      )
    '';

    meta = with lib; {
      description = "Paseo Desktop";
      homepage = "https://github.com/getpaseo/paseo";
      license = licenses.mit;
      platforms = ["x86_64-linux"];
      sourceProvenance = with sourceTypes; [binaryNativeCode];
      mainProgram = "paseo-desktop";
    };
  };
in
  package
