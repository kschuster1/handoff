#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

# plugin.json valid + named handoff
pj=$(cat "$ROOT/.claude-plugin/plugin.json")
assert_json_field "$pj" '.name' "handoff" "plugin.json name"
echo "$pj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "plugin.json is valid JSON"

# marketplace.json lives in .claude-plugin/ (where Claude Code looks for it) + lists the plugin
assert_eq "$([ -f "$ROOT/.claude-plugin/marketplace.json" ] && echo yes || echo no)" "yes" "marketplace.json in .claude-plugin/"
assert_eq "$([ -f "$ROOT/marketplace.json" ] && echo yes || echo no)" "no" "no stray marketplace.json at repo root"
mp=$(cat "$ROOT/.claude-plugin/marketplace.json")
echo "$mp" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "marketplace.json is valid JSON"
assert_contains "$mp" "handoff" "marketplace lists handoff"
# Claude Code schema requires an owner OBJECT (not string)
assert_json_field "$mp" '.owner | type' "object" "marketplace owner is an object (CC schema)"
assert_json_field "$mp" '.plugins[0].source' "./" "plugin source points at repo root"

# claude.json: events nested under a top-level `hooks` object (CC schema), claude arg, plugin root
hj=$(cat "$ROOT/hooks/claude.json")
echo "$hj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "claude.json is valid JSON"
assert_json_field "$hj" '.hooks | type' "object" "claude.json wraps events under top-level hooks object"
assert_json_field "$hj" '.hooks.SessionStart[0].hooks[0].type' "command" "SessionStart hook registered under .hooks"
assert_contains "$hj" "handoff-loader.sh" "claude.json calls the loader"
assert_contains "$hj" "claude" "claude.json passes claude arg"
assert_contains "$hj" "CLAUDE_PLUGIN_ROOT" "claude.json resolves via plugin root"

# command is the shared body (symlink resolves to same content)
assert_contains "$(cat "$ROOT/commands/handoff.md")" ".handoff/HANDOFF.md" "command body present (real file)"
finish
