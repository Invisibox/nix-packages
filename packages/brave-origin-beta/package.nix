{
  lib,
  pkgs,
}: let
  pname = "brave-origin-beta";
  version = "1.100.45";

  deps = with pkgs; [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    curl
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    gtk4
    libdrm
    libGL
    libgbm
    libkrb5
    libuuid
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxshmfence
    libxscrnsaver
    libxtst
    nspr
    nss
    pango
    pipewire
    qt6.qtbase
    snappy
    udev
    vulkan-loader
    wayland
    zlib
  ];

  rpath = lib.makeLibraryPath deps + ":" + lib.makeSearchPathOutput "lib" "lib64" deps;
  binpath = lib.makeBinPath deps;
in
  pkgs.stdenv.mkDerivation {
    inherit pname version;

    src = pkgs.fetchurl {
      url = "https://github.com/brave/brave-browser/releases/download/v${version}/brave-origin-beta_${version}_amd64.deb";
      hash = "sha256-wIUbaC78QDmL/w0fF3LlMR04ckw7YtcPG4hPC3xpUtc=";
    };

    dontConfigure = true;
    dontBuild = true;
    dontPatchELF = true;
    doInstallCheck = true;

    nativeBuildInputs = [
      pkgs.dpkg
      (pkgs.buildPackages.wrapGAppsHook3.override {makeWrapper = pkgs.buildPackages.makeShellWrapper;})
    ];

    buildInputs = with pkgs; [
      adwaita-icon-theme
      glib
      gsettings-desktop-schemas
      gtk3
      gtk4
    ];

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb --fsys-tarfile "$src" | tar --extract --no-same-owner --no-same-permissions
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/opt"
      cp -R opt "$out/"
      cp -R usr/share "$out/share"

      app_dir="$out/opt/brave.com/brave-origin-beta"
      browser_wrapper="$app_dir/brave-origin-beta"
      browser_binary="$app_dir/brave"

      rm -rf "$app_dir/cron"
      rm -f "$app_dir/libudev.so.0"
      rm -f "$app_dir/brave-origin"
      ln -s "$browser_wrapper" "$app_dir/brave-origin"

      substituteInPlace "$browser_wrapper" \
        --replace-fail "#!/bin/bash" "#!${pkgs.bash}/bin/bash"

      for exe in "$browser_binary" "$app_dir/chrome_crashpad_handler"; do
        patchelf \
          --set-interpreter "$(cat "$NIX_CC/nix-support/dynamic-linker")" \
          --set-rpath "${rpath}" \
          "$exe"
      done

      cat > "$out/bin/brave-origin-beta" <<'EOF'
      #!${pkgs.bash}/bin/bash
      XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}"

      USER_FLAGS=""
      USER_FLAGS_FILE="$XDG_CONFIG_HOME/brave-origin-beta-flags.conf"
      if [[ -f "$USER_FLAGS_FILE" ]]; then
        USER_FLAGS="$(sed 's/#.*//' "$USER_FLAGS_FILE")"
      fi

      export CHROME_USER_DATA_DIR="''${CHROME_USER_DATA_DIR:-$HOME/.config/BraveSoftware/Brave-Origin-Beta}"
      exec "@browser_wrapper@" $USER_FLAGS ''${BRAVE_FLAGS:-} ''${FLAG:-} "$@"
      EOF
      substituteInPlace "$out/bin/brave-origin-beta" \
        --replace-fail "@browser_wrapper@" "$browser_wrapper"
      chmod +x "$out/bin/brave-origin-beta"

      for desktop_file in "$out/share/applications/"*.desktop; do
        substituteInPlace "$desktop_file" \
          --replace-fail "/usr/bin/brave-origin-beta" "$out/bin/brave-origin-beta"
      done

      substituteInPlace "$app_dir/default-app-block" \
        --replace-fail "/opt/brave.com" "$out/opt/brave.com"

      for icon in 16 24 32 48 64 128 256; do
        install -d "$out/share/icons/hicolor/''${icon}x''${icon}/apps"
        logo="$app_dir/product_logo_''${icon}.png"
        if [[ ! -e "$logo" ]]; then
          logo="$app_dir/product_logo_''${icon}_beta.png"
        fi
        if [[ ! -e "$logo" ]]; then
          echo "missing icon asset: $logo" >&2
          exit 1
        fi
        ln -s "$logo" \
          "$out/share/icons/hicolor/''${icon}x''${icon}/apps/brave-origin-beta.png"
      done

      runHook postInstall
    '';

    preFixup = ''
      gappsWrapperArgs+=(
        --prefix LD_LIBRARY_PATH : ${rpath}
        --prefix PATH : ${binpath}
        --suffix PATH : ${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.xdg-utils
        ]
      }
        --set CHROME_WRAPPER ${pname}
        --add-flags "--disable-features=OutdatedBuildDetector"
      )
    '';

    installCheckPhase = ''
      "$out/opt/brave.com/brave-origin-beta/brave" --version
    '';

    meta = {
      description = "Minimalist browser from the makers of Brave";
      homepage = "https://brave.com/origin/";
      license = lib.licenses.mpl20;
      mainProgram = "brave-origin-beta";
      platforms = ["x86_64-linux"];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  }
