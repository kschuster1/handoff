#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
LOADER="$(dirname "$0")/../core/handoff-loader.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- no handoff, claude mode: cwd from stdin JSON ---
out=$(printf '{"cwd":"%s"}' "$TMP" | bash "$LOADER" claude)
assert_contains "$out" "No handoff for this project" "claude: no-handoff banner"
assert_contains "$out" "∅ No handoff available" "claude: no-handoff instruction line"

# --- no handoff, gemini mode: cwd from env, JSON output ---
out=$(GEMINI_CWD="$TMP" bash "$LOADER" gemini </dev/null)
assert_json_field "$out" '.hookSpecificOutput.hookEventName' "BeforeAgent" "gemini: hookEventName"
ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')
assert_contains "$ctx" "∅ No handoff available" "gemini: no-handoff inside additionalContext"

finish
