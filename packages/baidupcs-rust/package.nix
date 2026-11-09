{
  lib,
  stdenvNoCC,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
}: let
  pname = "baidupcs-rust";
  version = "2.4.0";
in
  stdenvNoCC.mkDerivation {
    inherit pname version;

    src = fetchurl {
      url = "https://github.com/komorebiCarry/BaiduPCS-Rust/releases/download/v${version}/BaiduPCS-Rust-v${version}-linux-x86_64.tar.gz";
      hash = "sha256-uCtKE22xGwyQHWxqWboP9qAaZyIuBOoZNtEdb50PTF8=";
    };

    nativeBuildInputs = [autoPatchelfHook makeWrapper];
    buildInputs = [stdenv.cc.cc.lib];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 baidu-netdisk-rust "$out/libexec/baidupcs-rust/baidu-netdisk-rust"
      cp -r frontend "$out/libexec/baidupcs-rust/"
      makeWrapper "$out/libexec/baidupcs-rust/baidu-netdisk-rust" "$out/bin/baidupcs-rust" \
        --run 'state_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/baidupcs-rust"; mkdir -p "$state_dir"; cd "$state_dir"'

      runHook postInstall
    '';

    meta = {
      description = "Open-source Baidu Netdisk client with a local web interface";
      homepage = "https://github.com/komorebiCarry/BaiduPCS-Rust";
      changelog = "https://github.com/komorebiCarry/BaiduPCS-Rust/releases/tag/v${version}";
      license = lib.licenses.asl20;
      mainProgram = "baidupcs-rust";
      platforms = ["x86_64-linux"];
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
