#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

# plugin.json valid + named handoff
pj=$(cat "$ROOT/.claude-plugin/plugin.json")
assert_json_field "$pj" '.name' "handoff" "plugin.json name"
echo "$pj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "plugin.json is valid JSON"

# marketplace.json lists the plugin
mp=$(cat "$ROOT/marketplace.json")
echo "$mp" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "marketplace.json is valid JSON"
assert_contains "$mp" "handoff" "marketplace lists handoff"

# hooks.json: SessionStart → loader with claude arg, uses plugin root var
hj=$(cat "$ROOT/hooks/hooks.json")
echo "$hj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "hooks.json is valid JSON"
assert_contains "$hj" "SessionStart" "hooks.json registers SessionStart"
assert_contains "$hj" "handoff-loader.sh" "hooks.json calls the loader"
assert_contains "$hj" "claude" "hooks.json passes claude arg"
assert_contains "$hj" "CLAUDE_PLUGIN_ROOT" "hooks.json resolves via plugin root"

# command is the shared body (symlink resolves to same content)
assert_contains "$(cat "$ROOT/commands/handoff.md")" ".handoff/HANDOFF.md" "command symlink resolves to shared body"
finish
