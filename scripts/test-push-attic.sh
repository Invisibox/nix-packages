#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
export ATTIC_TEST_ROOT="$test_root"
export ATTIC_TEST_SLEEP
ATTIC_TEST_SLEEP=$(command -v sleep)
mkdir -p "$test_root/bin"
cat > "$test_root/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$$" >> "$ATTIC_TEST_ROOT/timers"
exec "$ATTIC_TEST_SLEEP" 0.05
MOCK
cat > "$test_root/bin/attic" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  login)
    [[ $# == 4 && $2 == ci && $3 == "$ATTIC_SERVER" && $4 == "$ATTIC_TOKEN" ]]
    echo 'Configuring server "ci"'
    ;;
  push)
    printf '%s\n' "$@" > "$ATTIC_TEST_ROOT/args"
    if [[ "$ATTIC_TEST_MODE" == cancel ]]; then
      "$ATTIC_TEST_SLEEP" 120
    else
      "$ATTIC_TEST_SLEEP" 0.18
      if [[ "$ATTIC_TEST_MODE" == failure ]]; then
        echo 'HTTP 504 Gateway Timeout' >&2
        exit 17
      fi
      echo '✅ test-output'
    fi
    ;;
  *) exit 99 ;;
esac
MOCK
chmod +x "$test_root/bin/"*
export PATH="$test_root/bin:$PATH"
export ATTIC_SERVER=https://cache.example.invalid/ ATTIC_CACHE=test-cache
export ATTIC_TOKEN=test-token-must-not-appear
export OUTPUT_PATHS='["/nix/store/test-first","/nix/store/test-second"]'
unset ATTIC_PUSH_JOBS

for mode in success failure cancel; do
  export ATTIC_TEST_MODE=$mode
  : > "$test_root/timers"
  status=0
  if [[ "$mode" == cancel ]]; then
    timeout --kill-after=2s 0.5s "$repo_root/scripts/push-attic.sh" > "$test_root/$mode.log" 2>&1 || status=$?
  else
    "$repo_root/scripts/push-attic.sh" > "$test_root/$mode.log" 2>&1 || status=$?
  fi
  case "$mode:$status" in
    success:0|failure:17|cancel:124) ;;
    *) echo "FAIL: $mode returned $status"; exit 1 ;;
  esac
  grep -q 'Starting Attic push' "$test_root/$mode.log"
  grep -q 'Attic push is still running' "$test_root/$mode.log"
  if grep -q "$ATTIC_TOKEN" "$test_root/$mode.log"; then
    echo 'FAIL: token leaked'; exit 1
  fi
  printf '%s\n' push --jobs 1 ci:test-cache /nix/store/test-first /nix/store/test-second > "$test_root/expected-args"
  cmp "$test_root/expected-args" "$test_root/args"
  if [[ "$mode" == success ]]; then
    grep -q 'Attic push completed in' "$test_root/$mode.log"
  elif [[ "$mode" == failure ]]; then
    grep -q 'HTTP 504 Gateway Timeout' "$test_root/$mode.log"
    grep -q '::error::Attic push failed after .*exit 17' "$test_root/$mode.log"
    if grep -q 'Attic push completed' "$test_root/$mode.log"; then
      echo 'FAIL: upload failure reported as success'; exit 1
    fi
  fi
  while read -r pid; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "FAIL: timer $pid survived $mode"
      exit 1
    fi
  done < "$test_root/timers"
done

ATTIC_TEST_MODE=success ATTIC_PUSH_JOBS=2 "$repo_root/scripts/push-attic.sh" > "$test_root/parallel.log" 2>&1
printf '%s\n' push --jobs 2 ci:test-cache /nix/store/test-first /nix/store/test-second > "$test_root/expected-args"
cmp "$test_root/expected-args" "$test_root/args"
for jobs in 0 3 invalid; do
  rm -f "$test_root/args"
  if ATTIC_PUSH_JOBS="$jobs" "$repo_root/scripts/push-attic.sh" > "$test_root/invalid.log" 2>&1; then
    echo "FAIL: invalid upload jobs $jobs accepted"; exit 1
  fi
  [[ ! -e "$test_root/args" ]]
done
for outputs in '[]' '{}' 'null' '[null]' '["/tmp/wrong-path"]' '["/nix/store/first\n/nix/store/second"]'; do
  rm -f "$test_root/args"
  if OUTPUT_PATHS="$outputs" "$repo_root/scripts/push-attic.sh" > "$test_root/invalid.log" 2>&1; then
    echo "FAIL: invalid output paths $outputs accepted"; exit 1
  fi
  [[ ! -e "$test_root/args" ]]
done
if ATTIC_TOKEN='' "$repo_root/scripts/push-attic.sh" > "$test_root/invalid.log" 2>&1; then
  echo 'FAIL: missing token accepted'; exit 1
fi

echo 'Attic upload checks passed (batch outputs, concurrency, validation, failure status, progress, cancellation and credentials).'
