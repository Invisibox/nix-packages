#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_file="${repo_root}/packages/bottles/package.nix"
components_ref="${BOTTLES_COMPONENTS_REF:-main}"
components_index="${BOTTLES_COMPONENTS_INDEX:-index.yml}"
components_base="https://raw.githubusercontent.com/bottlesdevs/components/${components_ref}"
components_index_url="${components_base}/${components_index}"
winebridge_api_url="https://api.github.com/repos/bottlesdevs/winebridge/releases/latest"

if [[ ! -f "${package_file}" ]]; then
  echo "error: target file not found: ${package_file}" >&2
  exit 1
fi

for cmd in awk curl jq nix sed; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "error: missing command: ${cmd}" >&2
    exit 1
  fi
done

target_file="$(mktemp "${package_file}.XXXXXX")"
trap 'rm -f -- "${target_file}"' EXIT
cp -p -- "${package_file}" "${target_file}"

github_raw_headers=(-H "Accept: application/vnd.github.raw")
github_json_headers=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  github_raw_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  github_json_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

curl_fetch() {
  curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry "${CURL_RETRIES:-5}" \
    --retry-all-errors \
    --retry-delay "${CURL_RETRY_DELAY:-2}" \
    --retry-max-time "${CURL_RETRY_MAX_TIME:-120}" \
    --connect-timeout "${CURL_CONNECT_TIMEOUT:-20}" \
    "$@"
}

select_component() {
  local category="$1"
  local subcategory="$2"
  local prefix="$3"

  awk \
    -v wanted_category="${category}" \
    -v wanted_subcategory="${subcategory}" \
    -v wanted_prefix="${prefix}" '
      function reset_component(component_name) {
      name = component_name
        category_ok = 0
        channel_ok = 0
        subcategory_ok = (wanted_subcategory == "")
        prefix_ok = (wanted_prefix == "" || index(name, wanted_prefix) == 1)
      }

      function flush_component() {
        if (name != "" && category_ok && channel_ok && subcategory_ok && prefix_ok) {
          print name
          found = 1
          exit
        }
      }

      BEGIN {
      name = ""
        found = 0
      }

      /^[^#[:space:]][^:]*:$/ {
        flush_component()
        component_name = $0
        sub(/:$/, "", component_name)
        reset_component(component_name)
        next
      }

      name != "" && $1 == "Category:" && $2 == wanted_category {
        category_ok = 1
        next
      }

      name != "" && $1 == "Sub-category:" && $2 == wanted_subcategory {
        subcategory_ok = 1
        next
      }

      name != "" && $1 == "Channel:" && $2 == "stable" {
        channel_ok = 1
        next
      }

      END {
        if (!found) {
          flush_component()
        }
      }
    ' <<<"${components_index_yaml}"
}

manifest_value() {
  local key="$1"
  sed -n \
    -e "s/^[[:space:]]*-[[:space:]]*${key}:[[:space:]]*//p" \
    -e "s/^[[:space:]]*${key}:[[:space:]]*//p" \
    <<<"${manifest_yaml}" | head -n1
}

source_dir_from_file_name() {
  local file_name="$1"
  local source_dir="${file_name}"

  source_dir="${source_dir%.tar.gz}"
  source_dir="${source_dir%.tar.xz}"
  source_dir="${source_dir%.tgz}"
  source_dir="${source_dir%.zip}"

  printf '%s\n' "${source_dir}"
}

hash_from_digest() {
  local digest="$1"
  local hash=""

  if [[ -n "${digest}" && "${digest}" != "null" ]]; then
    local digest_algo="${digest%%:*}"
    local digest_hex="${digest#*:}"
    if [[ "${digest_algo}" == "sha256" && "${digest_hex}" =~ ^[0-9A-Fa-f]{64}$ ]]; then
      hash="$(nix hash convert --hash-algo sha256 --to sri "${digest_hex}" 2>/dev/null || true)"
    fi
  fi

  printf '%s\n' "${hash}"
}

github_asset_digest_hash() {
  local url="$1"
  local asset_name="$2"
  local hash=""

  if [[ "${url}" =~ ^https://github[.]com/([^/]+)/([^/]+)/releases/download/([^/]+)/(.+)$ ]]; then
    local owner="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"
    local release_tag="${BASH_REMATCH[3]}"
    local release_json asset_digest

    release_json="$(curl_fetch "${github_json_headers[@]}" "https://api.github.com/repos/${owner}/${repo}/releases/tags/${release_tag}")"
    asset_digest="$(
      jq -r --arg name "${asset_name}" '
        (
          [.assets[] | select(.name == $name)]
          | first
          | .digest
        ) // empty
      ' <<<"${release_json}"
    )"
    hash="$(hash_from_digest "${asset_digest}")"
  fi

  printf '%s\n' "${hash}"
}

github_asset_hash() {
  local url="$1"
  local asset_name="$2"
  local hash=""

  hash="$(github_asset_digest_hash "${url}" "${asset_name}")"

  if [[ -z "${hash}" || "${hash}" == "null" ]]; then
    hash="$(nix store prefetch-file --json "${url}" | jq -r '.hash')"
  fi

  if [[ -z "${hash}" || "${hash}" == "null" ]]; then
    echo "error: unable to determine hash for ${url}" >&2
    exit 1
  fi

  printf '%s\n' "${hash}"
}

read_info_value() {
  local attr="$1"
  local key="$2"

  sed -n "/^  ${attr} = {$/,/^  };$/s/^    ${key} = \"\\(.*\\)\";$/\\1/p" "${target_file}" | head -n1
}

update_info_block() {
  local attr="$1"
  local name="$2"
  local url="$3"
  local hash="$4"
  local source_dir="$5"

  sed -Ei "/^  ${attr} = \\{$/,/^  \\};$/s|^    name = \".*\";$|    name = \"${name}\";|" "${target_file}"
  sed -Ei "/^  ${attr} = \\{$/,/^  \\};$/s|^    url = \".*\";$|    url = \"${url}\";|" "${target_file}"
  sed -Ei "/^  ${attr} = \\{$/,/^  \\};$/s|^    hash = \"sha256-[^\"]+\";$|    hash = \"${hash}\";|" "${target_file}"
  sed -Ei "/^  ${attr} = \\{$/,/^  \\};$/s|^    sourceDir = \".*\";$|    sourceDir = \"${source_dir}\";|" "${target_file}"
}

update_component() {
  local attr="$1"
  local category="$2"
  local subcategory="$3"
  local prefix="$4"
  local manifest_dir="$5"

  local name
  name="$(select_component "${category}" "${subcategory}" "${prefix}")"
  if [[ -z "${name}" ]]; then
    echo "error: unable to find latest stable component for ${attr}" >&2
    exit 1
  fi

  manifest_yaml="$(curl_fetch "${github_raw_headers[@]}" "${components_base}/${manifest_dir}/${name}.yml")"

  local file_name url source_dir
  file_name="$(manifest_value "file_name")"
  url="$(manifest_value "url")"
  source_dir="$(source_dir_from_file_name "${file_name}")"

  if [[ -z "${file_name}" || -z "${url}" ]]; then
    echo "error: manifest missing file_name or url: ${manifest_dir}/${name}.yml" >&2
    exit 1
  fi

  local current_name current_url current_hash current_source_dir
  current_name="$(read_info_value "${attr}" "name")"
  current_url="$(read_info_value "${attr}" "url")"
  current_hash="$(read_info_value "${attr}" "hash")"
  current_source_dir="$(read_info_value "${attr}" "sourceDir")"

  local hash
  hash="$(github_asset_digest_hash "${url}" "${file_name}")"

  if [[ "${current_name}" == "${name}" \
    && "${current_url}" == "${url}" \
    && "${current_source_dir}" == "${source_dir}" \
    && -n "${current_hash}" \
    && ( -z "${hash}" || "${current_hash}" == "${hash}" ) ]]; then
    echo "${attr} is already up to date (${name})"
    return
  fi

  if [[ -z "${hash}" || "${hash}" == "null" ]]; then
    hash="$(github_asset_hash "${url}" "${file_name}")"
  fi

  update_info_block "${attr}" "${name}" "${url}" "${hash}" "${source_dir}"

  echo "updated ${attr}"
  echo "  name:      ${current_name:-unknown} -> ${name}"
  echo "  sourceDir: ${current_source_dir:-unknown} -> ${source_dir}"
  echo "  hash:      ${current_hash:-unknown} -> ${hash}"
  echo "  url:       ${url}"
}

update_winebridge() {
  local release_json release_info release_tag asset_name asset_url asset_digest
  local hash version current_version current_release_tag current_asset current_hash

  release_json="$(curl_fetch "${github_json_headers[@]}" "${winebridge_api_url}")"

  release_info="$(
    jq -r '
      . as $release
      | (
          [$release.assets[] | select(.name | test("^WineBridge-.*[.]tar[.]xz$"))]
          | first
        ) as $asset
      | select($release.draft == false)
      | select($asset.browser_download_url != null)
      | [$release.tag_name, $asset.name, $asset.browser_download_url, ($asset.digest // "")]
      | @tsv
    ' <<<"${release_json}"
  )"

  if [[ -z "${release_info}" ]]; then
    echo "error: unable to find a WineBridge tar.xz asset in the latest release" >&2
    exit 1
  fi

  IFS=$'\t' read -r release_tag asset_name asset_url asset_digest <<<"${release_info}"
  version="${release_tag#v}"

  current_version="$(sed -n 's/^  winebridgeVersion = "\(.*\)";$/\1/p' "${target_file}" | head -n1)"
  current_release_tag="$(sed -n 's/^  winebridgeReleaseTag = "\(.*\)";$/\1/p' "${target_file}" | head -n1)"
  current_asset="$(sed -n 's/^  winebridgeAsset = "\(.*\)";$/\1/p' "${target_file}" | head -n1)"
  current_hash="$(sed -n 's/^  winebridgeHash = "\(sha256-[^"]*\)";$/\1/p' "${target_file}" | head -n1)"

  hash="$(hash_from_digest "${asset_digest}")"

  if [[ "${current_version}" == "${version}" \
    && "${current_release_tag}" == "${release_tag}" \
    && "${current_asset}" == "${asset_name}" \
    && -n "${current_hash}" \
    && ( -z "${hash}" || "${current_hash}" == "${hash}" ) ]]; then
    echo "winebridge is already up to date (${version})"
    return
  fi

  if [[ -z "${hash}" || "${hash}" == "null" ]]; then
    hash="$(github_asset_hash "${asset_url}" "${asset_name}")"
  fi

  sed -Ei 's|^  winebridgeVersion = "[^"]+";$|  winebridgeVersion = "'"${version}"'";|' "${target_file}"
  sed -Ei 's|^  winebridgeReleaseTag = "[^"]+";$|  winebridgeReleaseTag = "'"${release_tag}"'";|' "${target_file}"
  sed -Ei 's|^  winebridgeAsset = "[^"]+";$|  winebridgeAsset = "'"${asset_name}"'";|' "${target_file}"
  sed -Ei 's|^  winebridgeHash = "sha256-[^"]+";$|  winebridgeHash = "'"${hash}"'";|' "${target_file}"

  echo "updated winebridge"
  echo "  release: ${current_release_tag:-unknown} -> ${release_tag}"
  echo "  version: ${current_version:-unknown} -> ${version}"
  echo "  asset:   ${current_asset:-unknown} -> ${asset_name}"
  echo "  hash:    ${current_hash:-unknown} -> ${hash}"
  echo "  url:     ${asset_url}"
}

update_winebridge

components_index_yaml="$(curl_fetch "${github_raw_headers[@]}" "${components_index_url}")"

update_component "runtimeComponentInfo" "runtimes" "" "runtime-" "runtimes"
update_component "dxvkComponentInfo" "dxvk" "" "dxvk-" "dxvk"
update_component "vkd3dComponentInfo" "vkd3d" "" "vkd3d-proton-" "vkd3d"
update_component "nvapiComponentInfo" "nvapi" "" "dxvk-nvapi-" "nvapi"
update_component "latencyflexComponentInfo" "latencyflex" "" "latencyflex-" "latencyflex"
update_component "caffeRunnerInfo" "runners" "wine" "caffe-" "runners/wine"
update_component "sodaRunnerInfo" "runners" "wine" "soda-" "runners/wine"

if ! cmp -s -- "${target_file}" "${package_file}"; then
  mv -- "${target_file}" "${package_file}"
fi
