#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_file="${repo_root}/packages/rime-wanxiang/package.nix"
headers=(-H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28')
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

fetch_release() {
  curl -fLsS --retry 3 --connect-timeout 20 --max-time 120 "${headers[@]}" \
    "https://api.github.com/repos/amzxyz/$1/releases/$2"
}

asset_hash() {
  local release="$1" url="$2" digest hash
  digest="$(jq -er --arg url "$url" '
    select(.draft == false and .prerelease == false) |
    first(.assets[] | select(.browser_download_url == $url)) |
    .digest // ""
  ' <<<"$release")" || {
    echo "error: missing release asset: $url" >&2
    return 1
  }
  if [[ "$digest" =~ ^sha256:[0-9a-fA-F]{64}$ ]]; then
    hash="$(nix hash convert --hash-algo sha256 --to sri "${digest#sha256:}")" || return
  else
    hash="$(nix store prefetch-file --json "$url" | jq -er .hash)" || return
  fi
  [[ "$hash" =~ ^sha256-[A-Za-z0-9+/]{43}=$ ]] || return 1
  printf '%s\n' "$hash"
}

schema_asset="$(sed -n 's/^  schemaAsset = "\([a-z0-9.-]*\)";$/\1/p' "$target_file")"
gram_asset="$(sed -n 's/^  gramAsset = "\([a-z0-9.-]*\)";$/\1/p' "$target_file")"
[[ -n "$schema_asset" && -n "$gram_asset" ]]
schema_release="$(fetch_release rime-wanxiang latest)"
tag="$(jq -er '.tag_name | select(test("^v[0-9]+([.][0-9]+)+$"))' <<<"$schema_release")"
version="${tag#v}"
schema_hash="$(asset_hash "$schema_release" "https://github.com/amzxyz/rime-wanxiang/releases/download/${tag}/${schema_asset}")"
gram_release="$(fetch_release rime-wanxiang-data tags/LTS)"
gram_hash="$(asset_hash "$gram_release" "https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/${gram_asset}")"

staged_file="$(mktemp "${target_file}.XXXXXX")"
trap 'rm -f -- "$staged_file"' EXIT
sed -E \
  -e "s|^  version = \"[^\"]+\";$|  version = \"${version}\";|" \
  -e "s|^  schemaHash = \"sha256-[^\"]+\";$|  schemaHash = \"${schema_hash}\";|" \
  -e "s|^  gramHash = \"sha256-[^\"]+\";$|  gramHash = \"${gram_hash}\";|" \
  "$target_file" > "$staged_file"

if cmp -s -- "$target_file" "$staged_file"; then
  echo "Rime Wanxiang is already up to date (${version})"
else
  chmod --reference="$target_file" "$staged_file"
  mv -- "$staged_file" "$target_file"
  echo "Updated Rime Wanxiang to ${version} with LTS model ${gram_hash}"
fi
