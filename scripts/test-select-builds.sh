#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
export SELECTOR_TEST_NIX
SELECTOR_TEST_NIX=$(command -v nix)
mkdir -p "$test_root/repo/scripts" "$test_root/bin"
cp "$repo_root/scripts/select-builds.sh" "$test_root/repo/scripts/"
cd "$test_root/repo"
git init -q
git config user.name Test
git config user.email test@example.org
cat > flake.nix <<'NIX'
{ outputs = { self }: {
  checks.x86_64-linux = builtins.mapAttrs (name: version: builtins.derivation {
    inherit name version;
    outputs = if name == "qq-jailed" then [ "out" "dev" ] else [ "out" ];
    system = "x86_64-linux";
    builder = "/bin/sh";
  }) (builtins.fromJSON (builtins.readFile ./versions.json));
}; }
NIX
cat > versions.json <<'JSON'
{"qq-jailed": "1", "wechat-jailed": "1", "jailed-desktop-policy": "1"}
JSON
cat > cache.json <<'JSON'
{"qq-jailed": "cached", "wechat-jailed": "cached", "jailed-desktop-policy": "cached"}
JSON
git add .
git commit -qm baseline
baseline=$(git rev-parse HEAD)

# Mock cache availability; keep real Nix evaluation and Git baseline handling.
cat > "$test_root/bin/nix" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 != run ]]; then
  exec "$SELECTOR_TEST_NIX" "$@"
fi
case "${SELECTOR_TEST_MODE-}" in
  error) printf '%s\n' '{"attr":"qq-jailed","error":"evaluation failed"}'; exit 0 ;;
  empty) exit 0 ;;
esac
"$SELECTOR_TEST_NIX" eval --json --no-write-lock-file '.#checks.x86_64-linux' --apply '
  builtins.mapAttrs (_: package: {
    inherit (package) drvPath system;
    outputs = builtins.listToAttrs (map (name: {
      inherit name;
      value = package.${name}.outPath;
    }) package.outputs);
  })
' | jq -c --slurpfile cache cache.json '
  to_entries[] | {attr: .key, cacheStatus: $cache[0][.key] // "notBuilt"} + .value
'
MOCK
chmod +x "$test_root/bin/nix"
export PATH="$test_root/bin:$PATH"
selector=./scripts/select-builds.sh

"$selector" "$baseline" | jq -e '.matrix == []' >/dev/null
jq '."qq-jailed" = "notBuilt"' cache.json > updated.json
mv updated.json cache.json
"$selector" "$baseline" | jq -e '
  (.matrix | length) == 1 and .matrix[0].attr == "qq-jailed" and
  .matrix[0].installable == ".#checks.x86_64-linux.qq-jailed" and
  (.matrix[0].outPaths | length == 2 and any(endswith("-qq-jailed-dev"))) and .matrix[0].policy == false
' >/dev/null

# Locally built updates still need a build job to publish their outputs to Cachix.
jq '."qq-jailed" = "local"' cache.json > updated.json
mv updated.json cache.json
"$selector" "$baseline" | jq -e '.matrix | length == 1' >/dev/null
jq '."qq-jailed" = "cached"' cache.json > updated.json
mv updated.json cache.json
jq '."qq-jailed" = "2"' versions.json > updated.json
mv updated.json versions.json
"$selector" "$baseline" | jq -e '.matrix == []' >/dev/null

jq '."jailed-desktop-policy" = "2" | del(."wechat-jailed")' versions.json > updated.json
mv updated.json versions.json
"$selector" "$baseline" | jq -e '.matrix | length == 1 and .[0].policy' >/dev/null
printf '{}\n' > cache.json
"$selector" "$baseline" | jq -e '.matrix | length == 2 and any(.policy)' >/dev/null
"$selector" 0000000000000000000000000000000000000000 | jq -e '.matrix | length == 2' >/dev/null

GITHUB_EVENT_NAME=schedule "$selector" | jq -e '.matrix | length == 2' >/dev/null
printf '{"before":"%s"}\n' "$baseline" > "$test_root/event.json"
GITHUB_EVENT_NAME=push GITHUB_EVENT_PATH="$test_root/event.json" "$selector" | jq -e '.matrix | length == 2' >/dev/null
printf '{"pull_request":{"base":{"sha":"%s"}}}\n' "$baseline" > "$test_root/event.json"
GITHUB_EVENT_NAME=pull_request GITHUB_EVENT_PATH="$test_root/event.json" "$selector" | jq -e '.matrix | length == 2' >/dev/null
printf '{"inputs":{"update":true}}\n' > "$test_root/event.json"
GITHUB_EVENT_NAME=workflow_dispatch GITHUB_EVENT_PATH="$test_root/event.json" "$selector" | jq -e '.matrix | length == 2' >/dev/null

cp flake.nix "$test_root/flake.nix"
printf 'invalid Nix\n' > flake.nix
git add flake.nix
git commit -qm 'broken baseline'
cp "$test_root/flake.nix" flake.nix
"$selector" HEAD 2>"$test_root/baseline.log" | jq -e '.matrix | length == 2' >/dev/null
grep -q 'Baseline evaluation failed' "$test_root/baseline.log"
printf '{"inputs":{"update":false}}\n' > "$test_root/event.json"
GITHUB_EVENT_NAME=workflow_dispatch GITHUB_EVENT_PATH="$test_root/event.json" "$selector" | jq -e '.matrix | length == 2' >/dev/null

for mode in error empty; do
  if SELECTOR_TEST_MODE="$mode" "$selector" "$baseline" > /dev/null 2>"$test_root/error.log"; then
    echo "FAIL: $mode evaluation was silently skipped" >&2
    exit 1
  fi
done
printf '{"qq-jailed":"unknown"}\n' > cache.json
if "$selector" "$baseline" > /dev/null 2>"$test_root/error.log"; then
  echo 'FAIL: unknown cache status was silently skipped' >&2
  exit 1
fi

echo 'Build selection checks passed (cache hit/miss, local update, policy, removal, baselines, events, evaluation errors).'
