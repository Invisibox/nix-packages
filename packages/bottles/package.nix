{
  pkgs,
  bottles,
}: let
  protonGePackage = pkgs.proton-ge-bin.overrideAttrs (_: {
    steamDisplayName = "Proton GE";
  });
  bottlesPackage = bottles.override {
    removeWarningPopup = true;
    # Keep the OpenLDAP test workaround in both architectures of the FHS runtime.
    buildFHSEnv = args:
      pkgs.buildFHSEnv (args
        // {
          multiPkgs = runtimePkgs:
            args.multiPkgs (runtimePkgs
              // {
                openldap = runtimePkgs.openldap.overrideAttrs (_: {doCheck = false;});
              });
        });
  };
  archiveNativeBuildInputs = with pkgs; [
    gnutar
    gzip
    unzip
    xz
  ];
  winebridgeVersion = "1.2.0";
  winebridgeReleaseTag = "1.2.0";
  winebridgeAsset = "WineBridge-75aa25e.tar.xz";
  winebridgeHash = "sha256-81yuP3fAtCRYw8rNIjd7zswkTNcQxQbICkRkYd1eBrw=";
  winebridge = pkgs.stdenvNoCC.mkDerivation {
    pname = "bottles-winebridge";
    version = winebridgeVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/bottlesdevs/winebridge/releases/download/${winebridgeReleaseTag}/${winebridgeAsset}";
      hash = winebridgeHash;
    };
    nativeBuildInputs = archiveNativeBuildInputs;
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall

      mkdir -p "$out/share/bottles/winebridge"
      cp -a ./. "$out/share/bottles/winebridge/"
      rm -f "$out/share/bottles/winebridge/env-vars"

      if [ ! -s "$out/share/bottles/winebridge/VERSION" ]; then
        printf '%s\n' "${winebridgeVersion}" > "$out/share/bottles/winebridge/VERSION"
      fi

      runHook postInstall
    '';
  };
  mkBottlesComponent = {
    pname,
    url,
    hash,
    installPath,
    sourceDir ? "",
    ...
  }:
    pkgs.stdenvNoCC.mkDerivation {
      name = pname;
      src = pkgs.fetchurl {
        inherit url hash;
      };
      nativeBuildInputs = archiveNativeBuildInputs;
      sourceRoot = ".";
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        runHook preInstall

        dest="$out/share/bottles/${installPath}"
        mkdir -p "$dest"

        if [ -n "${sourceDir}" ] && [ -d "${sourceDir}" ]; then
          cp -a "${sourceDir}/." "$dest/"
        else
          cp -a ./. "$dest/"
          rm -f "$dest/env-vars"
        fi

        runHook postInstall
      '';
    };
  mkBottlesRunner = {
    pname,
    url,
    hash,
    runnerName,
    sourceDir ? "",
    ...
  }:
    pkgs.stdenvNoCC.mkDerivation {
      name = pname;
      src = pkgs.fetchurl {
        inherit url hash;
      };
      nativeBuildInputs = archiveNativeBuildInputs;
      sourceRoot = ".";
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        runHook preInstall

        mkdir -p "$out/share/steam/compatibilitytools.d/${runnerName}"

        if [ -n "${sourceDir}" ] && [ -d "${sourceDir}" ]; then
          cp -a "${sourceDir}/." "$out/share/steam/compatibilitytools.d/${runnerName}/"
        else
          cp -a ./. "$out/share/steam/compatibilitytools.d/${runnerName}/"
          rm -f "$out/share/steam/compatibilitytools.d/${runnerName}/env-vars"
        fi

        chmod -R u+w "$out/share/steam/compatibilitytools.d/${runnerName}"
        find "$out/share/steam/compatibilitytools.d/${runnerName}" \
          -type f \
          -name winemenubuilder.exe \
          -exec sh -eu -c '
            for winemenubuilder do
              mv "$winemenubuilder" "$winemenubuilder.lock"
            done
          ' sh {} +

        runHook postInstall
      '';
    };
  runtimeComponentInfo = {
    name = "runtime-0.6.3";
    url = "https://github.com/bottlesdevs/runtime/releases/download/0.6.3/runtime-0.6.3.tar.gz";
    hash = "sha256-13SbSJJ714LhKONyodcIUTP74wDrkZMTTrgh9hvF+tY=";
    sourceDir = "runtime-0.6.3";
  };
  dxvkComponentInfo = {
    name = "dxvk-3.1.1";
    url = "https://github.com/doitsujin/dxvk/releases/download/v3.1.1/dxvk-3.1.1.tar.gz";
    hash = "sha256-QFZbSnJKrcRDP6TgELSyORbZsfG67uZOFxhtuU9U5gg=";
    sourceDir = "dxvk-3.1.1";
  };
  vkd3dComponentInfo = {
    name = "vkd3d-proton-3.1";
    url = "https://github.com/bottlesdevs/components/releases/download/vkd3d-proton-3.1/vkd3d-proton-3.1.tar.gz";
    hash = "sha256-r2xWzTxhcjStpeUpuYunENFR65SG9D8hg/YGq9ZfHHs=";
    sourceDir = "vkd3d-proton-3.1";
  };
  nvapiComponentInfo = {
    name = "dxvk-nvapi-v0.9.3";
    url = "https://github.com/bottlesdevs/components/releases/download/dxvk-nvapi-v0.9.3/dxvk-nvapi-v0.9.3.tar.gz";
    hash = "sha256-I0laIyhQmpJfSEPkZyFR8yfDrcE4Sc5SSN9E3Ktpp7Y=";
    sourceDir = "dxvk-nvapi-v0.9.3";
  };
  latencyflexComponentInfo = {
    name = "latencyflex-v0.1.1";
    url = "https://github.com/ishitatsuyuki/LatencyFleX/releases/download/v0.1.1/latencyflex-v0.1.1.tar.xz";
    hash = "sha256-yZLr0vQ8matKhKb/zmktmq5MwlcVNqWFSuLnm2lR54o=";
    sourceDir = "latencyflex-v0.1.1";
  };
  caffeRunnerInfo = {
    name = "caffe-10.0";
    url = "https://github.com/bottlesdevs/wine/releases/download/caffe-10.0/caffe-10.0-x86_64.tar.xz";
    hash = "sha256-z+lkL8Tb+736Kw78OT+x0j2Raq0VNcEE/fQ72VatZjY=";
    runnerName = "caffe-nix";
    sourceDir = "caffe-10.0-x86_64";
  };
  sodaRunnerInfo = {
    name = "soda-11.0-10";
    url = "https://github.com/bottlesdevs/wine/releases/download/soda-11.0-10/soda-11.0-10-x86_64.tar.xz";
    hash = "sha256-FGM/q9GA0wjSwevLhKFvNtBITd7VgJxk+KfJPmVNcpY=";
    runnerName = "soda-nix";
    sourceDir = "soda-11.0-10-x86_64";
  };
  runtimeComponent = mkBottlesComponent (runtimeComponentInfo
    // {
      pname = "bottles-${runtimeComponentInfo.name}";
      installPath = "runtimes/${runtimeComponentInfo.name}";
    });
  dxvkComponent = mkBottlesComponent (dxvkComponentInfo
    // {
      pname = "bottles-${dxvkComponentInfo.name}";
      installPath = "dxvk/${dxvkComponentInfo.name}";
    });
  vkd3dComponent = mkBottlesComponent (vkd3dComponentInfo
    // {
      pname = "bottles-${vkd3dComponentInfo.name}";
      installPath = "vkd3d/${vkd3dComponentInfo.name}";
    });
  nvapiComponent = mkBottlesComponent (nvapiComponentInfo
    // {
      pname = "bottles-${nvapiComponentInfo.name}";
      installPath = "nvapi/${nvapiComponentInfo.name}";
    });
  latencyflexComponent = mkBottlesComponent (latencyflexComponentInfo
    // {
      pname = "bottles-${latencyflexComponentInfo.name}";
      installPath = "latencyflex/${latencyflexComponentInfo.name}";
    });
  caffeRunner = mkBottlesRunner ({
      pname = caffeRunnerInfo.name;
    }
    // caffeRunnerInfo);
  sodaRunner = mkBottlesRunner ({
      pname = sodaRunnerInfo.name;
    }
    // sodaRunnerInfo);
in
  pkgs.symlinkJoin {
    pname = "bottles";
    inherit (bottlesPackage) version meta;
    # Keep every bundled component in the output closure so CI caches them too.
    paths = [
      bottlesPackage
      winebridge
      runtimeComponent
      dxvkComponent
      vkd3dComponent
      nvapiComponent
      latencyflexComponent
      caffeRunner
      sodaRunner
    ];
    postBuild = ''
      mkdir -p "$out/share/bottles/runners"
      ln -s ${protonGePackage.steamcompattool} "$out/share/bottles/runners/proton-ge-nix"
    '';
    passthru = {
      inherit
        protonGePackage
        winebridge
        runtimeComponent
        dxvkComponent
        vkd3dComponent
        nvapiComponent
        latencyflexComponent
        caffeRunner
        sodaRunner
        runtimeComponentInfo
        dxvkComponentInfo
        vkd3dComponentInfo
        nvapiComponentInfo
        latencyflexComponentInfo
        ;
      updateScript = pkgs.callPackage ../../lib/update-script.nix {
        script = "update-bottles.sh";
      };
    };
  }
