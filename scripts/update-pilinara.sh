#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_file="${repo_root}/packages/pilinara/package.nix"
headers=(-H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28')
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

release_json="$(curl -fLsS --retry 3 --connect-timeout 20 --max-time 120 \
  "${headers[@]}" 'https://api.github.com/repos/Starfallan/PiliNara/releases/latest')"
release_info="$(jq -er '
  select(.draft == false and .prerelease == false) |
  .tag_name as $tag |
  select($tag | test("^v?[0-9]+([.][0-9]+)+$")) |
  first(.assets[] | select(.name | test("^PiliNara_linux_.+_amd64[.]tar[.]gz$"))) |
  select(.browser_download_url | test("^https://github[.]com/Starfallan/PiliNara/releases/download/[A-Za-z0-9._%+/-]+$")) |
  [$tag, .browser_download_url, (.digest // "")] | @tsv
' <<<"${release_json}")"
IFS=$'\t' read -r release_tag asset_url asset_digest <<<"${release_info}"
version="${release_tag#v}"

if [[ "${asset_digest}" =~ ^sha256:[0-9a-fA-F]{64}$ ]]; then
  hash="$(nix hash convert --hash-algo sha256 --to sri "${asset_digest#sha256:}")"
else
  hash="$(nix store prefetch-file --json "${asset_url}" | jq -er .hash)"
fi
[[ "${hash}" =~ ^sha256-[A-Za-z0-9+/]{43}=$ ]]

staged_file="$(mktemp "${target_file}.XXXXXX")"
trap 'rm -f -- "${staged_file}"' EXIT
sed -E \
  -e "s|^  version = \"[^\"]+\";$|  version = \"${version}\";|" \
  -e "s|^      url = \"[^\"]+\";$|      url = \"${asset_url}\";|" \
  -e "s|^      hash = \"sha256-[^\"]+\";$|      hash = \"${hash}\";|" \
  "${target_file}" > "${staged_file}"

if cmp -s -- "${target_file}" "${staged_file}"; then
  echo "Pilinara is already up to date (${version})"
else
  chmod --reference="${target_file}" "${staged_file}"
  mv -- "${staged_file}" "${target_file}"
  echo "Updated Pilinara to ${version}: ${asset_url}"
fi
