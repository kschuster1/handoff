#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

# --- Codex marketplace manifest ---
cm=$(cat "$ROOT/.agents/plugins/marketplace.json")
echo "$cm" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "codex marketplace.json valid JSON"
assert_json_field "$cm" '.plugins[0].name' "handoff" "codex marketplace lists handoff"
assert_json_field "$cm" '.plugins[0].source.source' "local" "codex marketplace source type local"
assert_json_field "$cm" '.plugins[0].source.path' "./" "codex marketplace path points at repo root"

# --- Claude marketplace manifest points plugin at the release ref ---
am=$(cat "$ROOT/.claude-plugin/marketplace.json")
echo "$am" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "claude marketplace.json valid JSON"
assert_json_field "$am" '.plugins[0].source.source' "github" "claude plugin source type github"
assert_json_field "$am" '.plugins[0].source.repo' "kschuster1/handoff" "claude plugin source repo"
assert_json_field "$am" '.plugins[0].source.ref' "release" "claude plugin source pinned to release branch"
finish
