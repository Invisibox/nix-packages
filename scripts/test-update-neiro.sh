#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "${test_root}"' EXIT
export NEIRO_TEST_ROOT="${test_root}" NEIRO_TEST_REV="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
export NEIRO_TEST_SOURCE_HASH="sha256-VxtcACvqOKRBGYyTuQ3NoChJYVtG/A8SZFUpKtWXCRc="
export NEIRO_TEST_CARGO_HASH="sha256-LZrC1BFcQgqtPEYtvN7RKSoTgzA7NvHC0C3yBn/Jj8M="

fixture="${test_root}/repo with spaces"
mkdir -p "${fixture}/scripts" "${fixture}/packages/neiro" "${test_root}/bin"
cp "${repo_root}/scripts/update-neiro.sh" "${fixture}/scripts/"
cp "${repo_root}/packages/neiro/package.nix" "${test_root}/original.nix"
export NEIRO_TEST_TARGET="${fixture}/packages/neiro/package.nix"

# Mock only the upstream and Nix boundaries; use the real updater and file operations.
cat >"${test_root}/bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\tHEAD\n' "${NEIRO_TEST_REV}"
EOF
cat >"${test_root}/bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${NEIRO_TEST_MODE}" == "no_nix" ]]; then
  echo "unexpected Nix invocation" >&2
  exit 1
fi
case "$1 $2" in
  'store prefetch-file')
    jq -n --arg hash "${NEIRO_TEST_SOURCE_HASH}" --arg path "${NEIRO_TEST_ROOT}/source" \
      '{hash: $hash, storePath: $path}'
    ;;
  'eval --impure')
    # Same version, new revision: following main must still update.
    printf '0.2.0'
    ;;
  'build --impure')
    if [[ "$*" == *'.cargoDeps'* ]]; then
      if [[ "${NEIRO_TEST_MODE}" == "cargo_failure" ]]; then
        echo 'error: failed to download Cargo dependencies' >&2
      else
        printf 'error: hash mismatch in fixed-output derivation\n    got: %s\n' "${NEIRO_TEST_CARGO_HASH}" >&2
      fi
      exit 1
    fi
    case "${NEIRO_TEST_MODE}" in
      build_failure) echo 'error: upstream no longer builds' >&2; exit 1 ;;
      concurrent_edit) printf '\n# concurrent edit\n' >>"${NEIRO_TEST_TARGET}" ;;
    esac
    ;;
  *) echo "unexpected Nix command: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "${test_root}/bin/"*
export PATH="${test_root}/bin:${PATH}"
updater="${fixture}/scripts/update-neiro.sh"

fail() {
  cat "${test_root}/update.log" >&2
  echo "FAIL: $*" >&2
  exit 1
}

cp "${test_root}/original.nix" "${NEIRO_TEST_TARGET}"
NEIRO_TEST_MODE=success "${updater}" >"${test_root}/update.log" 2>&1 || fail 'successful update'
grep -Fq "rev = \"${NEIRO_TEST_REV}\";" "${NEIRO_TEST_TARGET}" || fail 'revision was not updated'
grep -Fq "hash = \"${NEIRO_TEST_SOURCE_HASH}\";" "${NEIRO_TEST_TARGET}" || fail 'source hash was not updated'
grep -Fq "cargoHash = \"${NEIRO_TEST_CARGO_HASH}\";" "${NEIRO_TEST_TARGET}" || fail 'Cargo hash was not updated'
[[ -r "${NEIRO_TEST_TARGET}" ]] || fail 'file permissions changed'

cp "${NEIRO_TEST_TARGET}" "${test_root}/updated.nix"
NEIRO_TEST_MODE=no_nix "${updater}" >"${test_root}/update.log" 2>&1 || fail 'up-to-date check'
cmp -s "${test_root}/updated.nix" "${NEIRO_TEST_TARGET}" || fail 'up-to-date file changed'

for mode in cargo_failure build_failure; do
  cp "${test_root}/original.nix" "${NEIRO_TEST_TARGET}"
  if NEIRO_TEST_MODE="${mode}" "${updater}" >"${test_root}/update.log" 2>&1; then
    fail "${mode} was not reported"
  fi
  cmp -s "${test_root}/original.nix" "${NEIRO_TEST_TARGET}" || fail "${mode} changed the package"
done

cp "${test_root}/original.nix" "${NEIRO_TEST_TARGET}"
if NEIRO_TEST_MODE=concurrent_edit "${updater}" >"${test_root}/update.log" 2>&1; then
  fail 'concurrent edit was not detected'
fi
cp "${test_root}/original.nix" "${test_root}/concurrent.nix"
printf '\n# concurrent edit\n' >>"${test_root}/concurrent.nix"
cmp -s "${test_root}/concurrent.nix" "${NEIRO_TEST_TARGET}" || fail 'concurrent edit was overwritten'

echo 'Neiro updater regression checks passed (update, no-op, Cargo failure, build failure, concurrent edit).'
