{
  lib,
  pkgs,
}: let
  pname = "baidunetdisk";
  version = "8.7.0";
  contents = pkgs.stdenvNoCC.mkDerivation {
    pname = "${pname}-unpacked";
    inherit version;
    src = pkgs.fetchurl {
      # Avoid pkg-ant's redirects to PCDN nodes on port 19001, unreachable in CI.
      url = "https://issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/8.7.0/baidunetdisk_8.7.0_amd64.deb";
      hash = "sha256-7HHCrRFRYJ/Q2LhtlRhMC0V9bbWqGIYeCxX8I8z+Afc=";
    };
    nativeBuildInputs = [pkgs.dpkg];
    dontConfigure = true;
    dontBuild = true;
    # Preserve vendor ELF files: patching them breaks netdisk_service.
    dontFixup = true;
    unpackPhase = ''dpkg-deb -x "$src" .'';
    installPhase = ''
      mkdir -p "$out"
      cp -r opt "$out/"
      cp -r usr/share "$out/share"
    '';
  };
in
  pkgs.buildFHSEnv {
    inherit pname version;
    includeClosures = true;
    targetPkgs = p:
      (with p; [
        alsa-lib
        at-spi2-core
        cups
        dbus
        gtk3
        libGL
        libayatana-appindicator
        libdrm
        libgbm
        libnotify
        libuuid
        libxcomposite
        libxdamage
        libxrandr
        libxt
        libxtst
        nspr
        nss
        systemdLibs
        xdg-utils
      ])
      ++ [(p.callPackage ./gtkmm2.nix {})];
    runScript = pkgs.writeShellScript "baidunetdisk-launch" ''
      exec ${contents}/opt/baidunetdisk/baidunetdisk --no-sandbox "$@"
    '';
    extraInstallCommands = ''cp -r ${contents}/share "$out/share"'';
    meta = {
      description = "Baidu Netdisk desktop client";
      homepage = "https://pan.baidu.com/";
      license = lib.licenses.unfree;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      mainProgram = "baidunetdisk";
      platforms = ["x86_64-linux"];
    };
  }
