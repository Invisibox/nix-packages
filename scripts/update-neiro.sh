#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_file="${repo_root}/packages/neiro/package.nix"
upstream="https://gitlab.com/wolf-yuan/neiro"

for cmd in git jq nix sed; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "error: missing command: ${cmd}" >&2
    exit 1
  fi
done

if [[ ! -f "${target_file}" ]]; then
  echo "error: target file not found: ${target_file}" >&2
  exit 1
fi

current_rev="$(sed -n 's/^    rev = "\([^"]*\)";$/\1/p' "${target_file}")"
current_version="$(sed -n 's/^  version = "\([^"]*\)";$/\1/p' "${target_file}")"
if [[ ! "${current_rev}" =~ ^[0-9a-f]{40}$ || -z "${current_version}" ]]; then
  echo "error: unable to locate current version/revision in ${target_file}" >&2
  exit 1
fi

rev="$(git ls-remote --exit-code "${upstream}.git" HEAD | cut -f1)"
if [[ ! "${rev}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: unable to determine upstream HEAD" >&2
  exit 1
fi
if [[ "${rev}" == "${current_rev}" ]]; then
  echo "neiro is already up to date (${current_version}, ${rev})"
  exit 0
fi

work_dir="$(mktemp -d)"
candidate="$(mktemp "${target_file}.XXXXXX")"
trap 'rm -rf -- "${work_dir}"; rm -f -- "${candidate}"' EXIT
cp -p "${target_file}" "${candidate}"
cp "${target_file}" "${work_dir}/original.nix"

echo "fetching neiro ${rev}"
source_json="$(nix store prefetch-file --unpack --name source --json \
  "${upstream}/-/archive/${rev}/neiro-${rev}.tar.gz")"
hash="$(jq -er '.hash' <<<"${source_json}")"
export NEIRO_UPDATE_SOURCE
NEIRO_UPDATE_SOURCE="$(jq -er '.storePath' <<<"${source_json}")"
if [[ ! "${hash}" =~ ^sha256-[A-Za-z0-9+/]{43}=$ ]]; then
  echo "error: invalid source hash: ${hash}" >&2
  exit 1
fi

version="$(nix eval --impure --raw --expr '
  (builtins.fromTOML (builtins.readFile
    ((builtins.getEnv "NEIRO_UPDATE_SOURCE") + "/Cargo.toml"))).package.version
')"
if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.+-]+)?$ ]]; then
  echo "error: invalid Cargo package version: ${version}" >&2
  exit 1
fi

sed -E \
  -e "s|^  version = \"[^\"]*\";$|  version = \"${version}\";|" \
  -e "s|^    rev = \"[^\"]*\";$|    rev = \"${rev}\";|" \
  -e "s|^    hash = \"[^\"]*\";$|    hash = \"${hash}\";|" \
  -e 's|^  cargoHash = .*;$|  cargoHash = lib.fakeHash;|' \
  "${work_dir}/original.nix" >"${candidate}"

export NEIRO_UPDATE_ROOT="${repo_root}" NEIRO_UPDATE_PACKAGE="${candidate}"
# Let Nix expand its own interpolation.
# shellcheck disable=SC2016
package_expr='
  let
    flake = builtins.getFlake (builtins.getEnv "NEIRO_UPDATE_ROOT");
    pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  in pkgs.callPackage (builtins.toPath (builtins.getEnv "NEIRO_UPDATE_PACKAGE")) {}
'

echo "determining Cargo dependency hash"
if nix build --impure --no-link --expr "(${package_expr}).cargoDeps" -L \
  >"${work_dir}/cargo.log" 2>&1; then
  echo "error: Cargo dependencies unexpectedly accepted the placeholder hash" >&2
  exit 1
fi
cargo_hash="$(sed -nE 's/^[[:space:]]+got:[[:space:]]+(sha256-[A-Za-z0-9+/]{43}=)[[:space:]]*$/\1/p' "${work_dir}/cargo.log")"
if [[ ! "${cargo_hash}" =~ ^sha256-[A-Za-z0-9+/]{43}=$ ]]; then
  cat "${work_dir}/cargo.log" >&2
  echo "error: Cargo dependency fetch failed without a usable hash" >&2
  exit 1
fi
sed -i "s|^  cargoHash = lib.fakeHash;$|  cargoHash = \"${cargo_hash}\";|" "${candidate}"

echo "building neiro ${version} (${rev}) and running its tests"
nix build --impure --no-link --expr "${package_expr}" -L

if ! cmp -s "${work_dir}/original.nix" "${target_file}"; then
  echo "error: ${target_file} changed during the update; leaving it untouched" >&2
  exit 1
fi
mv -f "${candidate}" "${target_file}"

echo "updated ${target_file}"
echo "  version:   ${current_version} -> ${version}"
echo "  revision:  ${current_rev} -> ${rev}"
echo "  hash:      ${hash}"
echo "  cargoHash: ${cargo_hash}"
