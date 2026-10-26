{
  lib,
  rustPlatform,
  fetchFromGitLab,
  pkg-config,
  makeWrapper,
  pipewire,
  wireplumber,
  ffmpeg,
}:
rustPlatform.buildRustPackage {
  pname = "neiro";
  version = "0.2.0";

  src = fetchFromGitLab {
    owner = "wolf-yuan";
    repo = "neiro";
    rev = "2c48e7eb41a45e603d0e3e2fb11227fdac32db2a";
    hash = "sha256-LZrC1BFcQgqtPEYtvN7RKSoTgzA7NvHC0C3yBn/Jj8M=";
  };

  cargoHash = "sha256-9v8xZLit/vrPjUSwdlVQtOuOw3jPdeDBJaS3+7/6Bck=";

  nativeBuildInputs = [pkg-config makeWrapper rustPlatform.bindgenHook];
  buildInputs = [pipewire];
  nativeCheckInputs = [ffmpeg];

  postInstall = ''
    wrapProgram "$out/bin/neiro" \
      --prefix PATH : ${lib.makeBinPath [pipewire wireplumber ffmpeg]}
    install -Dm644 samples/CREDITS.md "$out/share/doc/neiro/samples-CREDITS.md"
  '';

  meta = {
    description = "Laptop speaker enhancement using the laptop's Dolby DAX3 tuning";
    homepage = "https://gitlab.com/wolf-yuan/neiro";
    license = with lib.licenses; [gpl3Plus cc-by-30 cc-by-40];
    mainProgram = "neiro";
    platforms = lib.platforms.linux;
  };
}
