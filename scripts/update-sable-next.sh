#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_file="${repo_root}/packages/sable-next/package.nix"
upstream='https://git.sable.moe/SableClient/sable-next'

release_json="$(curl -fLsS --retry 3 --connect-timeout 20 --max-time 120 \
  'https://git.sable.moe/api/v1/repos/SableClient/sable-next/releases/latest')"
release_info="$(jq -er --arg upstream "${upstream}" '
  select(.draft == false and .prerelease == false) |
  .tag_name as $tag |
  select($tag | test("^v[0-9]+([.][0-9]+)+$")) |
  ("sable-" + ($tag | ltrimstr("v")) + "-amd64.deb") as $name |
  first(.assets[] | select(.name == $name)) |
  select(.browser_download_url == ($upstream + "/releases/download/" + $tag + "/" + $name)) |
  [$tag, $name] | @tsv
' <<<"${release_json}")"
IFS=$'\t' read -r release_tag asset_name <<<"${release_info}"
version="${release_tag#v}"

checksums="$(curl -fLsS --retry 3 --connect-timeout 20 --max-time 120 \
  "${upstream}/releases/download/${release_tag}/SHA256SUMS")"
digest="$(awk -v name="${asset_name}" '
  $2 == name && length($1) == 64 && $1 !~ /[^0-9a-fA-F]/ { print $1; count++ }
  END { if (count != 1) exit 1 }
' <<<"${checksums}")"
hash="$(nix hash convert --hash-algo sha256 --to sri "${digest}")"
[[ "${hash}" =~ ^sha256-[A-Za-z0-9+/]{43}=$ ]]

staged_file="$(mktemp "${target_file}.XXXXXX")"
trap 'rm -f -- "${staged_file}"' EXIT
sed -E \
  -e "s|^  version = \"[^\"]+\";$|  version = \"${version}\";|" \
  -e "s|^      hash = \"sha256-[^\"]+\";$|      hash = \"${hash}\";|" \
  "${target_file}" > "${staged_file}"

if cmp -s -- "${target_file}" "${staged_file}"; then
  echo "Sable Next is already up to date (${version})"
else
  chmod --reference="${target_file}" "${staged_file}"
  mv -- "${staged_file}" "${target_file}"
  echo "Updated Sable Next to ${version}"
fi
