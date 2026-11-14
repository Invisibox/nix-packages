{
  lib,
  pkgs,
}: let
  pname = "flectar-mail";
  version = "0.1.0-alpha.7";
in
  pkgs.stdenvNoCC.mkDerivation {
    inherit pname version;

    src = pkgs.fetchurl {
      url = "https://github.com/flectar/mail/releases/download/v${version}/flectar-mail_${lib.replaceStrings ["-"] ["."] version}_amd64.deb";
      hash = "sha256-KXL+bsDeQHWuAIJ41rzAGHFhVRuLdYg8saMMz0xV+C8=";
    };

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      dpkg
      makeWrapper
    ];
    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
      dbus
    ];
    # Slint/winit, Fontique and wgpu load these libraries with dlopen.
    runtimeDependencies = map lib.getLib (with pkgs; [
      fontconfig
      libGL
      libx11
      libxcb
      libxcursor
      libxi
      libxrandr
      libxkbcommon
      vulkan-loader
      wayland
    ]);

    dontConfigure = true;
    dontBuild = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x "$src" .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -a usr/bin usr/lib usr/share "$out/"
      wrapProgram "$out/bin/flectar-mail" \
        --prefix PATH : ${lib.makeBinPath [pkgs.gnupg pkgs.xdg-utils]}

      runHook postInstall
    '';

    passthru.updateScript = pkgs.callPackage ../../lib/update-script.nix {
      script = "update-flectar-mail.sh";
    };

    meta = {
      description = "Native email, calendar and contacts client built with Rust and Slint";
      homepage = "https://github.com/flectar/mail";
      changelog = "https://github.com/flectar/mail/releases/tag/v${version}";
      license = lib.licenses.agpl3Only;
      mainProgram = "flectar-mail";
      platforms = ["x86_64-linux"];
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
