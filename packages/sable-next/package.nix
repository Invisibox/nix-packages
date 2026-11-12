{
  lib,
  pkgs,
}: let
  pname = "sable-next";
  version = "2.3.8";

  runtimeLibs = with pkgs; [
    libGL
    libayatana-appindicator
    libnotify
    libpulseaudio
    libsecret
    pipewire
    udev
    vulkan-loader
    wayland
  ];
in
  pkgs.stdenv.mkDerivation {
    inherit pname version;

    src = pkgs.fetchurl {
      url = "https://git.sable.moe/SableClient/sable-next/releases/download/v${version}/sable-${version}-amd64.deb";
      hash = "sha256-JXhWI+HzmsGb091mmROV7antVscP8Q0RXLrDEWnXxwg=";
    };

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      desktop-file-utils
      dpkg
      wrapGAppsHook3
    ];
    buildInputs = with pkgs; [
      alsa-lib
      at-spi2-atk
      at-spi2-core
      cairo
      cups
      dbus
      expat
      glib
      gtk3
      libgbm
      libpulseaudio
      libx11
      libxcb
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxkbcommon
      libxrandr
      nspr
      nss
      pango
      pipewire
      stdenv.cc.cc.lib
      udev
    ];

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    dontWrapGApps = true;
    doInstallCheck = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb --fsys-tarfile "$src" | tar -x --no-same-owner --no-same-permissions
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib"
      cp -r opt/Sable "$out/lib/sable"
      cp -r usr/share "$out/share"
      substituteInPlace "$out/share/applications/moe.sable.client.desktop" \
        --replace-fail "Exec=/opt/Sable/sable" "Exec=$out/bin/sable"

      # The deb includes an arm64 helper unused on x86_64.
      rm "$out/lib/sable/resources/app.asar.unpacked/dist/venmic-arm64.node"
      # Electron uses the user namespace sandbox instead of a setuid helper.
      rm "$out/lib/sable/chrome-sandbox"
      # Nix provides the desktop entry and manages application updates.
      echo nix > "$out/lib/sable/resources/package-type"

      runHook postInstall
    '';

    postFixup = ''
      makeWrapper "$out/lib/sable/sable" "$out/bin/sable" \
        "''${gappsWrapperArgs[@]}" \
        --unset ELECTRON_RUN_AS_NODE \
        --unset APPIMAGE \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}:${pkgs.addDriverRunpath.driverLink}/lib" \
        --prefix PATH : ${lib.makeBinPath [pkgs.xdg-utils]}
    '';

    installCheckPhase = ''
      runHook preInstallCheck
      desktop-file-validate "$out/share/applications/moe.sable.client.desktop"
      # Bundled Electron disables RunAsNode; these modules use stable Node-API.
      ${lib.getExe pkgs.nodejs} -e '
        const path = require("node:path");
        for (const name of ["sable_node.node", "sable_audiofox.node", "venmic-x64.node"]) {
          require(path.join(process.argv[1], name));
        }
      ' "$out/lib/sable/resources/app.asar.unpacked/dist"
      runHook postInstallCheck
    '';

    passthru.updateScript = pkgs.callPackage ../../lib/update-script.nix {
      script = "update-sable-next.sh";
    };

    meta = {
      description = "Sable Next Matrix desktop client built with Rust and Svelte";
      homepage = "https://git.sable.moe/SableClient/sable-next";
      changelog = "https://git.sable.moe/SableClient/sable-next/releases/tag/v${version}";
      license = lib.licenses.agpl3Plus;
      mainProgram = "sable";
      platforms = ["x86_64-linux"];
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
