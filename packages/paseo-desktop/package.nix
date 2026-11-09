{
  lib,
  pkgs,
}: let
  pname = "paseo-desktop";
  version = "0.15.3";

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
    url = "https://github.com/getpaseo/paseo/releases/download/v${version}/Paseo-${version}-amd64.deb";
    hash = "sha256-tM5l/Vj1LW8GGppNKyVC34vlZerC71n3qiwfRIxASIM=";
  };

  package = pkgs.stdenv.mkDerivation {
    inherit pname version src;

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.dpkg
      (pkgs.buildPackages.wrapGAppsHook3.override {makeWrapper = pkgs.buildPackages.makeShellWrapper;})
    ];

    buildInputs =
      deps
      ++ (with pkgs; [
        adwaita-icon-theme
        gsettings-desktop-schemas
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

      mkdir -p "$out/bin"
      cp -R opt "$out/"
      cp -R usr/share "$out/share"

      makeWrapper "$out/opt/Paseo/Paseo" "$out/bin/paseo-desktop" \
        --unset ELECTRON_RUN_AS_NODE \
        --prefix XDG_DATA_DIRS : ${pkgs.xdg-utils}/share \
        --prefix PATH : ${lib.makeBinPath [xdgUtilsShim pkgs.xdg-utils]}

      mv "$out/share/applications/Paseo.desktop" "$out/share/applications/paseo-desktop.desktop"
      substituteInPlace "$out/share/applications/paseo-desktop.desktop" \
        --replace-fail "Exec=/opt/Paseo/Paseo" "Exec=$out/bin/paseo-desktop --class=Paseo"

      runHook postInstall
    '';

    preFixup = ''
      gappsWrapperArgs+=(
        --prefix LD_LIBRARY_PATH : ${rpath}:$out/opt/Paseo
      )
    '';

    installCheckPhase = ''
      runHook preInstallCheck
      ELECTRON_RUN_AS_NODE=1 "$out/opt/Paseo/Paseo.bin" \
        -e 'require("node:assert").ok(process.versions.electron)'
      runHook postInstallCheck
    '';

    passthru.updateScript = pkgs.callPackage ../../lib/update-script.nix {
      script = "update-paseo.sh";
    };

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
