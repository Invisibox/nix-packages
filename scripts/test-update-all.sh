#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
export UPDATE_ALL_TEST_ROOT="$test_root"
mkdir -p "$test_root/repo/scripts" "$test_root/bin"
cp "$repo_root/scripts/update-all.sh" "$test_root/repo/scripts/"
cat > "$test_root/bin/nix" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  eval)
    case "${UPDATE_ALL_TEST_MODE-}" in
      eval_failure) exit 1 ;;
      empty) printf '[]\n' ;;
      *) printf '["first", "second"]\n' ;;
    esac
    ;;
  run)
    printf '%s\n' "$*" >> "$UPDATE_ALL_TEST_ROOT/calls"
    if [[ "${UPDATE_ALL_TEST_MODE-}" == update_failure && "$*" == *'.first.updateScript'* ]]; then
      exit 1
    fi
    ;;
  flake)
    printf 'flake show\n' >> "$UPDATE_ALL_TEST_ROOT/calls"
    [[ "${UPDATE_ALL_TEST_MODE-}" != show_failure ]]
    ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$test_root/bin/nix"
export PATH="$test_root/bin:$PATH"
updater="$test_root/repo/scripts/update-all.sh"

"$updater" > "$test_root/output" 2>&1
grep -q '.#packages.x86_64-linux.first.updateScript' "$test_root/calls"
grep -q '.#packages.x86_64-linux.second.updateScript' "$test_root/calls"
grep -q 'flake show' "$test_root/calls"

for mode in update_failure show_failure eval_failure empty; do
  : > "$test_root/calls"
  if UPDATE_ALL_TEST_MODE="$mode" "$updater" > "$test_root/output" 2>&1; then
    echo "FAIL: $mode was not reported" >&2
    exit 1
  fi
  if [[ "$mode" == update_failure ]]; then
    grep -q '.second.updateScript' "$test_root/calls"
    grep -q 'flake show' "$test_root/calls"
  fi
done

echo 'Update discovery checks passed (package passthru, continued updates after failure, evaluation/validation errors, empty set).'
