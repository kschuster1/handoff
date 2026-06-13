#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

toml=$(cat "$ROOT/adapters/gemini/commands/handoff.toml")
assert_contains "$toml" "description" "gemini toml has description"
assert_contains "$toml" "prompt" "gemini toml has prompt"
assert_contains "$toml" "@{" "gemini toml @{}-includes the shared body"
assert_contains "$toml" "core/handoff.md" "gemini include points at shared body"
assert_contains "$toml" "{{args}}" "gemini toml forwards args"

hj=$(cat "$ROOT/adapters/gemini/hooks.json")
echo "$hj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "gemini hooks.json valid JSON"
assert_contains "$hj" "BeforeAgent" "gemini uses BeforeAgent event"
assert_contains "$hj" "handoff-loader.sh" "gemini calls loader"
assert_contains "$hj" "gemini" "gemini passes gemini arg"
finish
