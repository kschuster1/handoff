#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

toml=$(cat "$ROOT/adapters/gemini/commands/handoff.toml")
assert_contains "$toml" "description" "gemini toml has description"
assert_contains "$toml" "prompt" "gemini toml has prompt"
assert_contains "$toml" "@{" "gemini toml @{}-includes the shared body"
assert_contains "$toml" "core/handoff.md" "gemini include points at shared body"
assert_contains "$toml" "{{args}}" "gemini toml forwards args"

# Gemini hooks live in settings.json under .hooks.SessionStart (official schema)
sj=$(cat "$ROOT/adapters/gemini/settings.json")
echo "$sj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "gemini settings.json valid JSON"
assert_json_field "$sj" '.hooks.SessionStart[0].type' "command" "gemini hook under .hooks.SessionStart"
assert_contains "$sj" "SessionStart" "gemini uses SessionStart event (not BeforeAgent)"
assert_not_contains "$sj" "BeforeAgent" "gemini does NOT use per-prompt BeforeAgent"
assert_contains "$sj" "handoff-loader.sh" "gemini calls loader"
assert_contains "$sj" "gemini" "gemini passes gemini arg"
finish
