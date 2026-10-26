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
  nix eval --json --no-write-lock-file "$1#checks.x86_64-linux" \
    --apply 'builtins.mapAttrs (_: package: { drv = package.drvPath; path = package.outPath; })'
}

evaluate . > "$test_root/current.json"
printf '{}\n' > "$test_root/previous.json"
if [[ -n "$base_ref" ]] && git cat-file -e "$base_ref^{commit}" 2>/dev/null; then
  mkdir "$test_root/base"
  git archive "$base_ref" | tar -x -C "$test_root/base"
  if evaluate "path:$test_root/base" > "$test_root/baseline.json"; then
    mv "$test_root/baseline.json" "$test_root/previous.json"
  else
    echo 'Baseline evaluation failed; selecting all current outputs.' >&2
  fi
else
  echo 'No baseline commit; selecting all current outputs.' >&2
fi

# Comparing derivations also catches changes in shared code and locked inputs.
jq --slurpfile previous "$test_root/previous.json" '
  to_entries | map(select(.value.drv != $previous[0][.key].drv)) |
  {
    installables: map(".#checks.x86_64-linux." + .key),
    paths: (map(select(.key != "jailed-desktop-policy") | .value.path) | join(" ")),
    policy: any(.key == "jailed-desktop-policy")
  }
' "$test_root/current.json"
