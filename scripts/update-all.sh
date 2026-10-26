#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
self_name="${BASH_SOURCE[0]##*/}"

update_scripts=()
shopt -s nullglob
for script_path in "${script_dir}"/update-*.sh; do
  script_name="${script_path##*/}"
  if [[ "${script_name}" == "${self_name}" ]]; then
    continue
  fi

  update_scripts+=("${script_path}")
done
shopt -u nullglob

if (( ${#update_scripts[@]} == 0 )); then
  echo "error: no update scripts found in ${script_dir}" >&2
  exit 1
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "error: missing command: nix" >&2
  exit 1
fi

cd "${repo_root}"

failures=()

for script_path in "${update_scripts[@]}"; do
  script_name="${script_path##*/}"

  if [[ ! -x "${script_path}" ]]; then
    echo "error: update script is not executable: ${script_path}" >&2
    failures+=("${script_name} (not executable)")
    continue
  fi

  echo
  echo "==> ${script_name}"
  if "${script_path}"; then
    echo "==> ${script_name} completed"
  else
    status=$?
    echo "error: ${script_name} failed with exit status ${status}" >&2
    failures+=("${script_name} (${status})")
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
