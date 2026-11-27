{
  lib,
  pkgs,
}: let
  pname = "fluxdown";
  version = "0.6.9";
  repo = "https://github.com/zerx-lab/FluxDown";
in
  pkgs.stdenvNoCC.mkDerivation {
    inherit pname version;

    src = pkgs.fetchurl {
      url = "${repo}/releases/download/v${version}/FluxDown-${version}-linux-x64.deb";
      hash = "sha256-GUY0fHJYWIqyHbFeiAV4hjYdfjhm07gFZyYYPxx7l8Y=";
    };

    nativeBuildInputs = with pkgs; [autoPatchelfHook dpkg makeWrapper wrapGAppsHook3];
    buildInputs = with pkgs; [
      alsa-lib
      cairo
      dbus
      fontconfig
      freetype
      gdk-pixbuf
      glib
      gsettings-desktop-schemas
      gtk3
      libayatana-appindicator
      libx11
      libxcb
      libxkbcommon
      pango
      stdenv.cc.cc.lib
      vulkan-loader
      wayland
      xdotool
      zlib
      zstd
    ];
    # GPUI and tray support can load libraries dynamically. Keep them on the
    # ELF search path even when an agent or browser starts a helper directly.
    runtimeDependencies = with pkgs; [libayatana-appindicator libglvnd libx11 libxkbcommon vulkan-loader wayland];

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    dontWrapGApps = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x "$src" .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      # Each executable locates its helpers relative to current_exe.
      appDir="$out/libexec/fluxdown"
      mkdir -p "$appDir" "$out/bin"
      install -m755 opt/fluxdown/{fluxdown-desktop,fluxdown-agent,fluxdownd,fluxdown_nmh} "$appDir/"
      cp -r usr/share "$out/"

      runHook postInstall
    '';

    postFixup = ''
      for bin in fluxdown-desktop fluxdown-agent; do
        makeWrapper "$out/libexec/fluxdown/$bin" "$out/bin/$bin" \
          "''${gappsWrapperArgs[@]}" \
          --prefix PATH : ${lib.makeBinPath [pkgs.xdg-utils]}
      done
    '';

    passthru.updateScript = pkgs.callPackage ../../lib/update-script.nix {
      script = "update-fluxdown.sh";
    };

    meta = {
      description = "Native download manager for HTTP, FTP, BitTorrent, and streaming media";
      homepage = "https://fluxdown.com";
      changelog = "${repo}/releases/tag/v${version}";
      license = lib.licenses.agpl3Only;
      mainProgram = "fluxdown-desktop";
      platforms = ["x86_64-linux"];
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
