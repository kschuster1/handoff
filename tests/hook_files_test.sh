#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

# A default hooks/hooks.json must NOT exist (it would auto-load and double-wire).
assert_eq "$([ -f "$ROOT/hooks/hooks.json" ] && echo present || echo absent)" "absent" "no default hooks/hooks.json"

# Claude hook file: valid JSON, uses CLAUDE_PLUGIN_ROOT, has SessionStart+SessionEnd+PreCompact.
cj=$(cat "$ROOT/hooks/claude.json")
echo "$cj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "claude.json valid JSON"
assert_contains "$cj" "\${CLAUDE_PLUGIN_ROOT}" "claude.json uses CLAUDE_PLUGIN_ROOT"
assert_contains "$cj" "handoff-loader.sh" "claude.json wires loader"
assert_json_field "$cj" '.hooks.SessionStart[0].hooks[0].type' "command" "claude SessionStart present"
assert_json_field "$cj" '.hooks.SessionEnd[0].hooks[0].type' "command" "claude SessionEnd present"
assert_json_field "$cj" '.hooks.PreCompact[0].hooks[0].type' "command" "claude PreCompact present"

# Codex hook file: valid JSON, uses plugin-root-relative ./core paths (figma pattern: Codex
# runs plugin hooks with cwd=plugin root), SessionStart+PreCompact, and NO SessionEnd.
xj=$(cat "$ROOT/hooks/codex.json")
echo "$xj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "codex.json valid JSON"
assert_contains "$xj" "./core/handoff-loader.sh" "codex.json uses plugin-root-relative path"
assert_not_contains "$xj" "PLUGIN_ROOT" "codex.json does not rely on \${PLUGIN_ROOT} (uses relative ./core)"
assert_not_contains "$xj" "CLAUDE_PLUGIN_ROOT" "codex.json does not use CLAUDE_PLUGIN_ROOT"
assert_json_field "$xj" '.hooks.SessionStart[0].hooks[0].type' "command" "codex SessionStart present"
assert_json_field "$xj" '.hooks.PreCompact[0].hooks[0].type' "command" "codex PreCompact present"
assert_eq "$(echo "$xj" | jq -r '.hooks | has("SessionEnd")')" "false" "codex.json has NO SessionEnd (not a Codex event)"
assert_contains "$xj" "HANDOFF_EVENT=PreCompact" "codex PreCompact carries HANDOFF_EVENT"

# Claude manifest points at the custom hooks file.
pj=$(cat "$ROOT/.claude-plugin/plugin.json")
assert_json_field "$pj" '.hooks' "./hooks/claude.json" "claude manifest references ./hooks/claude.json"
finish
