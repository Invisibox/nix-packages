{
  lib,
  pkgs,
}: let
  pname = "rime-wanxiang";
  version = "18.2.0";
  schemaAsset = "rime-wanxiang-flypy-fuzhu.zip";
  schemaHash = "sha256-ACdenBHx+EPdc+P+KICraCkYUM+TvmdyS/K8fz/ZnhY=";
  gramAsset = "wanxiang-lts-zh-hans.gram";
  gramHash = "sha256-6d3VAbfVNrxeoTRvj5AK5JpxmgW+NJ4KF8sn5xcUPKU=";
  gram = pkgs.fetchurl {
    url = "https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/${gramAsset}";
    hash = gramHash;
  };
in
  pkgs.stdenvNoCC.mkDerivation {
    inherit pname version;

    src = pkgs.fetchurl {
      url = "https://github.com/amzxyz/rime-wanxiang/releases/download/v${version}/${schemaAsset}";
      hash = schemaHash;
    };

    nativeBuildInputs = [pkgs.unzip];
    dontConfigure = true;
    dontBuild = true;

    unpackPhase = ''
      runHook preUnpack
      unzip -q "$src"

      shopt -s dotglob nullglob
      entries=(*)
      if [ "''${#entries[@]}" -eq 1 ] && [ -d "''${entries[0]}" ]; then
        cd "''${entries[0]}"
      fi
      shopt -u dotglob nullglob
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      if [ -f README.md ]; then
        install -Dm644 README.md "$out/share/doc/${pname}/README.md"
      fi
      if [ -f LICENSE ]; then
        install -Dm644 LICENSE "$out/share/licenses/${pname}/LICENSE"
      fi
      rm -rf README.md LICENSE .git* env-vars
      if [ -d custom ]; then
        find custom -type f ! -name '*.yaml' -delete
      fi
      mv default.yaml wanxiang_suggested_default.yaml

      mkdir -p "$out/share/rime-data"
      cp -r . "$out/share/rime-data/"
      ln -sf '${gram}' "$out/share/rime-data/${gramAsset}"
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      data="$out/share/rime-data"
      test -s "$data/wanxiang_pro.schema.yaml"
      test -s "$data/wanxiang_algebra.yaml"
      test -s "$data/wanxiang_suggested_default.yaml"
      test -s "$data/${gramAsset}"
      runHook postInstallCheck
    '';

    passthru.updateScript = pkgs.callPackage ../../lib/update-script.nix {
      script = "update-rime-wanxiang.sh";
    };

    meta = {
      description = "Wanxiang Rime schema with Xiaohe double pinyin, auxiliary codes, and the Simplified Chinese LTS language model";
      homepage = "https://github.com/amzxyz/rime-wanxiang";
      changelog = "https://github.com/amzxyz/rime-wanxiang/releases/tag/v${version}";
      license = lib.licenses.cc-by-40;
      platforms = lib.platforms.all;
    };
  }
