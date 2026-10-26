#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_file="${repo_root}/packages/paseo-desktop/package.nix"
api_url="https://api.github.com/repos/getpaseo/paseo/releases/latest"
asset_pattern="Paseo-x86_64.AppImage"
package_name="paseo-desktop"

if [[ ! -f "${target_file}" ]]; then
  echo "error: target file not found: ${target_file}" >&2
  exit 1
fi

for cmd in curl head jq nix sed; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "error: missing command: ${cmd}" >&2
    exit 1
  fi
done

github_headers=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  github_headers=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

release_json="$(curl -fsSL "${github_headers[@]}" "${api_url}")"

tag_name="$(jq -r '.tag_name // empty' <<<"${release_json}")"
if [[ -z "${tag_name}" ]]; then
  echo "error: unable to read latest release tag from ${api_url}" >&2
  exit 1
fi

version="${tag_name#v}"

asset_info="$(jq -r --arg pattern "${asset_pattern}" '
  (
    .assets[]
    | select(.name == $pattern)
    | [.browser_download_url, (.digest // "")]
    | @tsv
  ) // empty
' <<<"${release_json}")"

if [[ -z "${asset_info}" ]]; then
  echo "error: release ${tag_name} has no asset named ${asset_pattern}" >&2
  exit 1
fi

IFS=$'\t' read -r asset_url asset_digest <<<"${asset_info}"

hash=""
if [[ -n "${asset_digest}" ]]; then
  digest_algo="${asset_digest%%:*}"
  digest_hex="${asset_digest#*:}"
  if [[ "${digest_algo}" == "sha256" && "${digest_hex}" =~ ^[0-9A-Fa-f]{64}$ ]]; then
    hash="$(nix hash convert --hash-algo sha256 --to sri "${digest_hex}" 2>/dev/null || true)"
  fi
fi

if [[ -z "${hash}" || "${hash}" == "null" ]]; then
  hash="$(nix store prefetch-file --json "${asset_url}" | jq -r '.hash')"
fi

if [[ -z "${hash}" || "${hash}" == "null" ]]; then
  echo "error: unable to determine hash for ${asset_url}" >&2
  exit 1
fi

current_version="$(sed -n 's/^  version = "\(.*\)";$/\1/p' "${target_file}" | head -n1)"
current_hash="$(sed -n 's/^    hash = "\(sha256-[^"]*\)";$/\1/p' "${target_file}" | head -n1)"

if [[ -z "${current_version}" || -z "${current_hash}" ]]; then
  echo "error: unable to locate current version/hash in ${target_file}" >&2
  exit 1
fi

if [[ "${current_version}" == "${version}" && "${current_hash}" == "${hash}" ]]; then
  echo "${package_name} is already up to date (${version})"
  exit 0
fi

sed -Ei 's|^  version = "[^"]+";$|  version = "'"${version}"'";|' "${target_file}"
sed -Ei '0,/^    hash = "sha256-[^"]+";$/s|^    hash = "sha256-[^"]+";$|    hash = "'"${hash}"'";|' "${target_file}"

updated_version="$(sed -n 's/^  version = "\(.*\)";$/\1/p' "${target_file}" | head -n1)"
updated_hash="$(sed -n 's/^    hash = "\(sha256-[^"]*\)";$/\1/p' "${target_file}" | head -n1)"

if [[ "${updated_version}" != "${version}" || "${updated_hash}" != "${hash}" ]]; then
  echo "error: failed to update version/hash in ${target_file}" >&2
  exit 1
fi

echo "updated ${target_file}"
echo "  version: ${current_version:-unknown} -> ${version}"
echo "  hash:    ${current_hash:-unknown} -> ${hash}"
echo "  asset:   ${asset_url}"
