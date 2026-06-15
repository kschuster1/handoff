#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

stage=$(mktemp -d)
( cd "$ROOT" && HANDOFF_RELEASE_STAGE="$stage" bash scripts/build-release.sh ) >/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "build-release stage mode exits 0"

# Required runtime files present
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json \
         .codex-plugin/plugin.json .agents/plugins/marketplace.json \
         hooks/claude.json hooks/codex.json \
         core/handoff-loader.sh core/handoff-snapshot.sh core/handoff.md \
         commands/handoff.md README.md LICENSE; do
  assert_eq "$([ -f "$stage/$f" ] && echo y || echo n)" "y" "release includes $f"
done

# Dev-only files must NOT ship
assert_eq "$([ -d "$stage/docs" ] && echo y || echo n)" "n" "release excludes docs/"
assert_eq "$([ -d "$stage/tests" ] && echo y || echo n)" "n" "release excludes tests/"
assert_eq "$([ -f "$stage/hooks/hooks.json" ] && echo y || echo n)" "n" "release has no default hooks.json"
assert_eq "$([ -d "$stage/.git" ] && echo y || echo n)" "n" "release excludes .git"
rm -rf "$stage"
finish
