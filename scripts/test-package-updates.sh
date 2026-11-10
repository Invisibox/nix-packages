#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
export PACKAGE_UPDATE_TEST_NIX PACKAGE_UPDATE_TEST_ROOT="$test_root"
PACKAGE_UPDATE_TEST_NIX=$(command -v nix)
fixture="$test_root/repo with spaces"
mkdir -p "$fixture/scripts" "$fixture/packages/pilinara" "$fixture/packages/bottles" "$test_root/bin"
cp "$repo_root/scripts/update-pilinara.sh" "$repo_root/scripts/update-bottles.sh" "$fixture/scripts/"
cp "$repo_root/packages/pilinara/package.nix" "$fixture/packages/pilinara/"
cp "$repo_root/packages/bottles/package.nix" "$fixture/packages/bottles/"
cp "$fixture/packages/pilinara/package.nix" "$test_root/pilinara.original"
cp "$fixture/packages/bottles/package.nix" "$test_root/bottles.original"

# Mock upstream responses and downloads; keep the real parsers and hash conversion.
cat > "$test_root/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
url=${!#}
digest="sha256:$(printf '%064d' 0)"
case "$url" in
  *Starfallan/PiliNara/releases/latest)
    [[ ${PACKAGE_UPDATE_TEST_MODE-} != network_failure ]] || exit 22
    jq -n --arg digest "$digest" --arg mode "${PACKAGE_UPDATE_TEST_MODE-}" '
      {
        tag_name: "2.7.0", draft: ($mode == "draft"), prerelease: false,
        assets: (if $mode == "missing_asset" then [] else [{
          name: "PiliNara_linux_2.2.0+9999_amd64.tar.gz",
          browser_download_url: "https://github.com/Starfallan/PiliNara/releases/download/2.7.0/PiliNara_linux_2.2.0%2B9999_amd64.tar.gz",
          digest: (if $mode == "missing_digest" then null else $digest end)
        }] end)
      }
    '
    ;;
  *bottlesdevs/winebridge/releases/latest)
    jq -n --arg digest "$digest" '{tag_name: "1.3.0", draft: false, assets: [{
      name: "WineBridge-new.tar.xz", digest: $digest,
      browser_download_url: "https://github.com/bottlesdevs/winebridge/releases/download/1.3.0/WineBridge-new.tar.xz"
    }]}'
    ;;
  */components/main/index.yml)
    for entry in 'runtime:runtimes' 'dxvk:dxvk' 'vkd3d-proton:vkd3d' 'dxvk-nvapi:nvapi' 'latencyflex:latencyflex' 'caffe:runners' 'soda:runners'; do
      printf '%s-99.0:\n  Category: %s\n  Channel: stable\n  Sub-category: wine\n' "${entry%:*}" "${entry#*:}"
    done
    ;;
  */components/main/*.yml)
    [[ ${PACKAGE_UPDATE_TEST_MODE-} != bottles_failure || "$url" != */dxvk/* ]] || exit 22
    component=${url##*/}
    component=${component%.yml}
    file_name="$component.tar.xz"
    [[ "$component" != caffe-* && "$component" != soda-* ]] || file_name="$component-x86_64.tar.xz"
    printf 'file_name: %s\nurl: https://github.com/test/components/releases/download/v99/%s\n' "$file_name" "$file_name"
    ;;
  */releases/tags/*)
    jq -n --arg digest "$digest" '{assets: [
      "runtime", "dxvk", "vkd3d-proton", "dxvk-nvapi", "latencyflex", "caffe", "soda"
    ] | map({name: (. + "-99.0" + (if . == "caffe" or . == "soda" then "-x86_64" else "" end) + ".tar.xz"), digest: $digest})}'
    ;;
  *) echo "Unexpected URL: $url" >&2; exit 1 ;;
esac
MOCK
cat > "$test_root/bin/nix" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" == 'store prefetch-file' ]]; then
  printf 'prefetch\n' >> "$PACKAGE_UPDATE_TEST_ROOT/downloads"
  printf '{"hash":"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}\n'
else
  exec "$PACKAGE_UPDATE_TEST_NIX" "$@"
fi
MOCK
chmod +x "$test_root/bin/"*
export PATH="$test_root/bin:$PATH"
pilinara="$fixture/packages/pilinara/package.nix"
bottles="$fixture/packages/bottles/package.nix"

bash "$fixture/scripts/update-pilinara.sh" > "$test_root/update.log"
grep -q 'version = "2.7.0";' "$pilinara"
grep -q 'download/2.7.0/PiliNara_linux_2.2.0%2B9999_amd64.tar.gz' "$pilinara"
grep -q 'sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' "$pilinara"
[[ ! -e "$test_root/downloads" ]]
bash "$fixture/scripts/update-pilinara.sh" > "$test_root/update.log"
grep -q 'already up to date' "$test_root/update.log"
for mode in network_failure missing_asset draft; do
  cp "$test_root/pilinara.original" "$pilinara"
  if PACKAGE_UPDATE_TEST_MODE="$mode" bash "$fixture/scripts/update-pilinara.sh" > "$test_root/update.log" 2>&1; then
    echo "FAIL: Pilinara $mode was accepted" >&2
    exit 1
  fi
  cmp "$test_root/pilinara.original" "$pilinara"
done
PACKAGE_UPDATE_TEST_MODE=missing_digest bash "$fixture/scripts/update-pilinara.sh" > "$test_root/update.log"
grep -q prefetch "$test_root/downloads"

bash "$fixture/scripts/update-bottles.sh" > "$test_root/update.log"
grep -q 'winebridgeVersion = "1.3.0";' "$bottles"
for component in runtime dxvk vkd3d-proton dxvk-nvapi latencyflex caffe soda; do
  grep -q "name = \"$component-99.0\";" "$bottles"
done
grep -q 'sourceDir = "caffe-99.0-x86_64";' "$bottles"
grep -q 'runnerName = "caffe-nix";' "$bottles"
bash "$fixture/scripts/update-bottles.sh" > "$test_root/update.log"
[[ $(grep -c 'already up to date' "$test_root/update.log") == 8 ]]
cp "$test_root/bottles.original" "$bottles"
if PACKAGE_UPDATE_TEST_MODE=bottles_failure bash "$fixture/scripts/update-bottles.sh" > "$test_root/update.log" 2>&1; then
  echo 'FAIL: Bottles accepted a failed component update' >&2
  exit 1
fi
cmp "$test_root/bottles.original" "$bottles"

echo 'Package updater checks passed (release filenames, hashes, all Bottles components, no-op updates, atomic failures).'
