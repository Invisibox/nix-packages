#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_file="${repo_root}/packages/oxideterm/package.nix"
api_url="https://api.github.com/repos/AnalyseDeCircuit/oxideterm/releases/latest"

if [[ ! -f "${target_file}" ]]; then
  echo "error: target file not found: ${target_file}" >&2
  exit 1
fi

for cmd in curl jq nix sed; do
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

asset_info="$(jq -r --arg v "${version}" '
  (
    .assets[]
    | select(.name == ("OxideTerm_" + $v + "_linux_x64.deb"))
    | [.browser_download_url, (.digest // "")]
    | @tsv
  ) // empty
' <<<"${release_json}")"

if [[ -z "${asset_info}" ]]; then
  echo "error: release ${tag_name} has no asset named OxideTerm_${version}_linux_x64.deb" >&2
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

if [[ "${current_version}" == "${version}" && "${current_hash}" == "${hash}" ]]; then
  echo "oxide-term is already up to date (${version})"
  exit 0
fi

sed -Ei 's|^  version = "[^"]+";$|  version = "'"${version}"'";|' "${target_file}"
sed -Ei 's|^    hash = "sha256-[^"]+";$|    hash = "'"${hash}"'";|' "${target_file}"

echo "updated ${target_file}"
echo "  version: ${current_version:-unknown} -> ${version}"
echo "  hash:    ${current_hash:-unknown} -> ${hash}"
echo "  asset:   ${asset_url}"
