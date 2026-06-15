#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

pj=$(cat "$ROOT/.codex-plugin/plugin.json")
echo "$pj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "codex plugin.json valid JSON"
assert_json_field "$pj" '.name' "handoff" "codex manifest name = handoff (matches claude)"
# Codex auto-discovers hooks from hooks.json at the plugin root (figma pattern) — NO manifest
# override (a manifest-pointed custom hooks path does not register; verified live).
assert_eq "$(echo "$pj" | jq -r 'has("hooks")')" "false" "codex manifest has NO hooks override (root hooks.json auto-discovered)"
assert_eq "$(echo "$pj" | jq -r 'has("version")')" "true" "codex manifest has version"
assert_eq "$(echo "$pj" | jq -r 'has("description")')" "true" "codex manifest has description"

# Versions must stay in lockstep with the Claude manifest.
cv=$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")
xv=$(echo "$pj" | jq -r '.version')
assert_eq "$xv" "$cv" "codex manifest version matches claude manifest version"
finish
