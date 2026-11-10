#!/usr/bin/env bash
set -euo pipefail

: "${ATTIC_SERVER:?Set ATTIC_SERVER}"
: "${ATTIC_CACHE:?Set ATTIC_CACHE}"
: "${ATTIC_TOKEN:?Set the ATTIC_TOKEN repository secret}"
push_jobs=${ATTIC_PUSH_JOBS:-2}
if [[ ! "$push_jobs" =~ ^[1-2]$ ]]; then
  echo 'ATTIC_PUSH_JOBS must be 1 or 2.' >&2
  exit 1
fi
output_list=$(jq -er '
  select(type == "array" and length > 0 and
    all(.[]; type == "string" and startswith("/nix/store/") and (contains("\n") | not))) |
  .[]
' <<< "${OUTPUT_PATHS:?Set OUTPUT_PATHS to a JSON array of store paths}")
mapfile -t output_paths <<< "$output_list"

attic login ci "$ATTIC_SERVER" "$ATTIC_TOKEN"
printf 'Starting Attic push to %s (cache: %s, upload jobs: %s).\n' "$ATTIC_SERVER" "$ATTIC_CACHE" "$push_jobs"
printf '  Output: %s\n' "${output_paths[@]}"
started_at=$SECONDS
# Attic hides its terminal progress bars in Actions, so report elapsed time.
(
  trap 'exit 0' TERM INT
  trap '[[ -z ${timer_pid:-} ]] || kill "$timer_pid" 2>/dev/null || true' EXIT
  while true; do
    sleep 30 &
    timer_pid=$!
    wait "$timer_pid"
    printf 'Attic push is still running (%ss elapsed); waiting for transfer/server response.\n' "$((SECONDS - started_at))"
  done
) &
progress_pid=$!
trap 'kill "$progress_pid" 2>/dev/null || true; wait "$progress_pid" 2>/dev/null || true' EXIT

# All outputs are known: plan their shared closure once before starting workers.
if attic push --jobs "$push_jobs" "ci:$ATTIC_CACHE" "${output_paths[@]}"; then
  printf 'Attic push completed in %ss.\n' "$((SECONDS - started_at))"
else
  status=$?
  printf '::error::Attic push failed after %ss (exit %s).\n' "$((SECONDS - started_at))" "$status"
  exit "$status"
fi
