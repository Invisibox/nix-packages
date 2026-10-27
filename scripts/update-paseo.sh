#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

exec nix run --no-write-lock-file --inputs-from . 'nixpkgs#nix-update' -- \
  --flake --use-github-releases paseo-desktop
