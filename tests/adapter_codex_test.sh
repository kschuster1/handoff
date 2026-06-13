#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

hj=$(cat "$ROOT/adapters/codex/hooks.json")
echo "$hj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "codex hooks.json valid JSON"
assert_json_field "$hj" '.hooks.SessionStart[0].hooks[0].type' "command" "codex SessionStart under top-level hooks object"
assert_contains "$hj" "handoff-loader.sh" "codex calls loader"
assert_contains "$hj" "codex" "codex passes codex arg"

assert_contains "$(cat "$ROOT/adapters/codex/prompts/handoff.md")" ".handoff/HANDOFF.md" "codex prompt body present (real file)"
finish
