{
  lib,
  writeShellApplication,
  bash,
  coreutils,
  curl,
  git,
  gnused,
  jq,
  nix,
  script,
}:
writeShellApplication {
  name = lib.removeSuffix ".sh" script;
  runtimeInputs = [bash coreutils curl git gnused jq nix];
  text = ''
    cd "$(git rev-parse --show-toplevel)"
    exec bash "./scripts/${script}" "$@"
  '';
}
