#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_file="${repo_root}/packages/brave-origin-beta/package.nix"
api_url="https://api.github.com/repos/brave/brave-browser/releases?per_page=30"
package_name="brave-origin-beta"

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

github_headers=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  github_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

releases_json="$(curl -fsSL "${github_headers[@]}" "${api_url}")"

release_info="$(
  jq -r --arg package_name "${package_name}" '
    .[]
    | . as $release
    | ($release.tag_name | ltrimstr("v")) as $version
    | (
        $release.assets[]
        | select(.name == ($package_name + "_" + $version + "_amd64.deb"))
      ) as $asset
    | [$version, $asset.browser_download_url, ($asset.digest // "")]
    | @tsv
  ' <<<"${releases_json}" | head -n1
)"

if [[ -z "${release_info}" ]]; then
  echo "error: unable to find a ${package_name} amd64 deb in recent Brave releases" >&2
  exit 1
fi

IFS=$'\t' read -r version asset_url asset_digest <<<"${release_info}"

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
current_hash="$(sed -n 's/^      hash = "\(sha256-[^"]*\)";$/\1/p' "${target_file}" | head -n1)"

if [[ -z "${current_version}" || -z "${current_hash}" ]]; then
  echo "error: unable to locate current version/hash in ${target_file}" >&2
  exit 1
fi

if [[ "${current_version}" == "${version}" && "${current_hash}" == "${hash}" ]]; then
  echo "${package_name} is already up to date (${version})"
  exit 0
fi

sed -Ei 's|^  version = "[^"]+";$|  version = "'"${version}"'";|' "${target_file}"
sed -Ei 's|^      hash = "sha256-[^"]+";$|      hash = "'"${hash}"'";|' "${target_file}"

updated_version="$(sed -n 's/^  version = "\(.*\)";$/\1/p' "${target_file}" | head -n1)"
updated_hash="$(sed -n 's/^      hash = "\(sha256-[^"]*\)";$/\1/p' "${target_file}" | head -n1)"

if [[ "${updated_version}" != "${version}" || "${updated_hash}" != "${hash}" ]]; then
  echo "error: failed to update version/hash in ${target_file}" >&2
  exit 1
fi

echo "updated ${target_file}"
echo "  version: ${current_version:-unknown} -> ${version}"
echo "  hash:    ${current_hash:-unknown} -> ${hash}"
echo "  asset:   ${asset_url}"
