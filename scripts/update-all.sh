#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

if ! command -v nix >/dev/null 2>&1; then
  echo "error: missing command: nix" >&2
  exit 1
fi

cd "${repo_root}"

packages_json="$(nix eval --json --no-write-lock-file '.#packages.x86_64-linux' --apply '
  packages: builtins.filter (name: (builtins.getAttr name packages) ? updateScript) (builtins.attrNames packages)
')"
mapfile -t packages < <(jq -r '.[]' <<<"${packages_json}")
if (( ${#packages[@]} == 0 )); then
  echo 'error: no packages export updateScript' >&2
  exit 1
fi

failures=()

for package in "${packages[@]}"; do
  echo
  echo "==> ${package}"
  if nix run --no-write-lock-file ".#packages.x86_64-linux.${package}.updateScript"; then
    echo "==> ${package} completed"
  else
    status=$?
    echo "error: ${package} failed with exit status ${status}" >&2
    failures+=("${package} (${status})")
  fi
done

echo
echo "==> nix flake show --no-write-lock-file"
if nix flake show --no-write-lock-file "${repo_root}" >/dev/null; then
  echo "==> nix flake show completed"
else
  status=$?
  echo "error: nix flake show failed with exit status ${status}" >&2
  failures+=("nix flake show (${status})")
fi

if (( ${#failures[@]} > 0 )); then
  echo
  echo "update scripts completed with failures:" >&2
  for failure in "${failures[@]}"; do
    echo "  - ${failure}" >&2
  done
  exit 1
fi

echo
echo "all update scripts completed"
