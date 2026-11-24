#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
input_pattern='^(    url = "git\+https://git\.sable\.moe/SableClient/sable-next\?ref=refs/tags/)(v[0-9]+(\.[0-9]+){2})(&shallow=1";)$'
current_tag="$(sed -nE "s|${input_pattern}|\\2|p" "$repo_root/flake.nix")"
if [[ ! "$current_tag" =~ ^v[0-9]+(\.[0-9]+){2}$ ]]; then
  echo 'error: expected one versioned sable-next input URL in flake.nix' >&2
  exit 1
fi

release_json="$(curl -fLsS --retry 3 --connect-timeout 20 --max-time 120 \
  https://git.sable.moe/api/v1/repos/SableClient/sable-next/releases/latest)"
release_tag="$(jq -er '
  select(.draft == false and .prerelease == false) |
  .tag_name | select(type == "string" and test("^v[0-9]+([.][0-9]+){2}\\z"))
' <<<"$release_json")" || {
  echo 'error: Forgejo did not return a versioned stable Sable Next release' >&2
  exit 1
}

if [[ "$release_tag" == "$current_tag" ]]; then
  echo "Sable Next is already up to date ($current_tag)"
  exit 0
fi

# Update the lock against the new tag before replacing either live file.
staged_dir="$(mktemp -d "$repo_root/.sable-next-update.XXXXXX")"
trap 'rm -rf -- "$staged_dir"' EXIT
sed -E "s|${input_pattern}|\\1${release_tag}\\4|" "$repo_root/flake.nix" > "$staged_dir/flake.nix"
cp -- "$repo_root/flake.lock" "$staged_dir/flake.lock"
nix flake update sable-next --flake "path:$staged_dir"
mv -- "$staged_dir/flake.nix" "$staged_dir/flake.lock" "$repo_root/"
echo "Updated Sable Next from $current_tag to $release_tag"
