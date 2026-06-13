#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

hj=$(cat "$ROOT/adapters/codex/hooks.json")
echo "$hj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "codex hooks.json valid JSON"
assert_contains "$hj" "SessionStart" "codex registers SessionStart"
assert_contains "$hj" "handoff-loader.sh" "codex calls loader"
assert_contains "$hj" "codex" "codex passes codex arg"

assert_contains "$(cat "$ROOT/adapters/codex/prompts/handoff.md")" ".handoff/HANDOFF.md" "codex prompt symlink resolves to shared body"
finish
