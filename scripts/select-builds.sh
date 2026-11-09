#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

if (( $# )); then
  base_ref=$1
else
  case "${GITHUB_EVENT_NAME-}" in
    push) base_ref=$(jq -r '.before' "$GITHUB_EVENT_PATH") ;;
    pull_request) base_ref=$(git merge-base "$(jq -r '.pull_request.base.sha' "$GITHUB_EVENT_PATH")" HEAD) ;;
    workflow_dispatch)
      if jq -e '.inputs.update == true or .inputs.update == "true"' "$GITHUB_EVENT_PATH" >/dev/null; then
        base_ref=HEAD
      else
        base_ref=HEAD^
      fi
      ;;
    *) base_ref=HEAD ;;
  esac
fi

evaluate() {
  nix eval --raw --no-write-lock-file "$1#checks.x86_64-linux.jailed-desktop-policy.drvPath"
}

nix run --no-write-lock-file --inputs-from . 'nixpkgs#nix-eval-jobs' -- \
  --flake '.#checks.x86_64-linux' --check-cache-status --workers 2 > "$test_root/current.json"
previous_policy=""
if [[ -n "$base_ref" ]] && git cat-file -e "$base_ref^{commit}" 2>/dev/null; then
  mkdir "$test_root/base"
  git archive "$base_ref" | tar -x -C "$test_root/base"
  if evaluate "path:$test_root/base" > "$test_root/previous-policy"; then
    previous_policy=$(cat "$test_root/previous-policy")
  else
    echo 'Baseline evaluation failed; scheduling the sandbox policy check.' >&2
  fi
else
  echo 'No baseline commit; scheduling the sandbox policy check.' >&2
fi

# Check actual cache availability, so evicted or previously failed builds are retried.
jq --slurp --arg previous_policy "$previous_policy" \
  --argjson cache_backfill "${CACHE_BACKFILL:-false}" '
  if length == 0 then error("No derivations were evaluated")
  elif any(.error != null) then error(map(select(.error != null)) | tojson)
  elif any(.system != "x86_64-linux" or
    (.cacheStatus != "cached" and .cacheStatus != "local" and .cacheStatus != "notBuilt"))
  then error("Unexpected system or cache status")
  else . end |
  {
    matrix: map(
      select(if .attr == "jailed-desktop-policy" then .drvPath != $previous_policy
        else $cache_backfill or .cacheStatus != "cached" end) |
      {
        attr,
        installable: (".#checks.x86_64-linux." + .attr),
        outPaths: [.outputs[]],
        policy: (.attr == "jailed-desktop-policy")
      }
    )
  }
' "$test_root/current.json"
