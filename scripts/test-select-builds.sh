#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/repo/scripts"
cp "$repo_root/scripts/select-builds.sh" "$test_root/repo/scripts/"
cd "$test_root/repo"
git init -q
git config user.name Test
git config user.email test@example.org
cat > flake.nix <<'EOF'
{ outputs = { self }: {
  checks.x86_64-linux = builtins.mapAttrs (name: version: builtins.derivation {
    inherit name version;
    system = "x86_64-linux";
    builder = "/bin/sh";
  }) (builtins.fromJSON (builtins.readFile ./versions.json));
}; }
EOF
cat > versions.json <<'EOF'
{
  "qq-jailed": "1",
  "wechat-jailed": "1",
  "jailed-desktop-policy": "1"
}
EOF
git add .
git commit -qm baseline
baseline=$(git rev-parse HEAD)

selector=./scripts/select-builds.sh

"$selector" "$baseline" | jq -e '.installables == [] and .paths == "" and .policy == false' >/dev/null
jq '."qq-jailed" = "2"' versions.json > updated.json
mv updated.json versions.json
"$selector" "$baseline" | jq -e '.installables == [".#checks.x86_64-linux.qq-jailed"] and (.paths | endswith("-qq-jailed")) and .policy == false' >/dev/null
jq '."jailed-desktop-policy" = "2" | del(."wechat-jailed")' versions.json > updated.json
mv updated.json versions.json
"$selector" "$baseline" | jq -e '(.installables | length) == 2 and (.paths | endswith("-qq-jailed")) and .policy == true' >/dev/null
"$selector" 0000000000000000000000000000000000000000 | jq -e '(.installables | length) == 2 and .policy == true' >/dev/null

# Scheduled updates compare the modified worktree with the checked-out HEAD.
GITHUB_EVENT_NAME=schedule "$selector" | jq -e '(.installables | length) == 2' >/dev/null
printf '{"before":"%s"}\n' "$baseline" > "$test_root/event.json"
GITHUB_EVENT_NAME=push GITHUB_EVENT_PATH="$test_root/event.json" "$selector" | jq -e '(.installables | length) == 2' >/dev/null
printf '{"pull_request":{"base":{"sha":"%s"}}}\n' "$baseline" > "$test_root/event.json"
GITHUB_EVENT_NAME=pull_request GITHUB_EVENT_PATH="$test_root/event.json" "$selector" | jq -e '(.installables | length) == 2' >/dev/null
printf '{"inputs":{"update":true}}\n' > "$test_root/event.json"
GITHUB_EVENT_NAME=workflow_dispatch GITHUB_EVENT_PATH="$test_root/event.json" "$selector" | jq -e '(.installables | length) == 2' >/dev/null

# A broken old flake must select current outputs instead of silently skipping them.
cp flake.nix "$test_root/flake.nix"
printf 'invalid Nix\n' > flake.nix
git add flake.nix
git commit -qm 'broken baseline'
cp "$test_root/flake.nix" flake.nix
"$selector" HEAD 2>"$test_root/baseline.log" | jq -e '(.installables | length) == 2 and .policy == true' >/dev/null
grep -q 'Baseline evaluation failed' "$test_root/baseline.log"
printf '{"inputs":{"update":false}}\n' > "$test_root/event.json"
GITHUB_EVENT_NAME=workflow_dispatch GITHUB_EVENT_PATH="$test_root/event.json" "$selector" | jq -e '(.installables | length) == 2' >/dev/null
echo 'Build selection checks passed (no-op, package, policy, removal, missing/failed baseline, schedule, push, PR, manual).'
