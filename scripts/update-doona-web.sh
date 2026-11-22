#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

exec nix run --no-write-lock-file --impure --file ./lib/nix-update.nix '' -- \
  --flake --use-github-releases --version=unstable \
  --version-regex '^(v[0-9]+\.[0-9]+\.[0-9]+(?:-(?:alpha|beta|rc)\.[0-9]+)?)$' \
  --url https://github.com/Zakkaus/doona doona-web
