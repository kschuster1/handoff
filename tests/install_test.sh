#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$ROOT/install.sh"

FH=$(mktemp -d)            # fake HOME
mkdir -p "$FH/.codex" "$FH/.gemini"   # pretend codex + gemini are installed; claude absent

HANDOFF_FAKE_HOME="$FH" bash "$INSTALL" --yes >/dev/null 2>&1

# codex prompt + hooks placed, placeholder resolved
assert_eq "$([ -e "$FH/.codex/prompts/handoff.md" ] && echo yes || echo no)" "yes" "codex prompt installed"
hooks=$(cat "$FH/.codex/hooks.json" 2>/dev/null || echo "")
assert_contains "$hooks" "$ROOT/core/handoff-loader.sh" "codex hooks path resolved to repo abs path"
assert_not_contains "$hooks" "{{HANDOFF_ROOT}}" "codex placeholder fully resolved"

# gemini command placed, include resolved
gt=$(cat "$FH/.gemini/commands/handoff.toml" 2>/dev/null || echo "")
assert_contains "$gt" "@{$ROOT/core/handoff.md}" "gemini include resolved to abs path"

# gemini hook lands in settings.json under .hooks.SessionStart, path resolved
gs=$(cat "$FH/.gemini/settings.json" 2>/dev/null || echo "{}")
assert_json_field "$gs" '.hooks.SessionStart[0].command | contains("'"$ROOT"'/core/handoff-loader.sh")' "true" "gemini settings.json hook resolved to abs path"
assert_not_contains "$gs" "{{HANDOFF_ROOT}}" "gemini settings placeholder resolved"

# claude not installed → skipped cleanly (no dir created)
assert_eq "$([ -d "$FH/.claude/plugins" ] && echo yes || echo no)" "no" "absent harness skipped"

# idempotency: second run does not duplicate or error
HANDOFF_FAKE_HOME="$FH" bash "$INSTALL" --yes >/dev/null 2>&1
assert_eq "$?" "0" "second install run is idempotent (exit 0)"

# idempotency: our SessionStart hook entry appears exactly once after two runs
n=$(jq '[.SessionStart[].hooks[].command | select(contains("handoff-loader.sh"))] | length' "$FH/.codex/hooks.json")
assert_eq "$n" "1" "codex: handoff hook present exactly once after 2 runs (no dupes)"

# non-destructive merge: a pre-existing unrelated hook survives installation
FH2=$(mktemp -d); mkdir -p "$FH2/.codex"
printf '{"PreToolUse":[{"hooks":[{"type":"command","command":"my-own-guard"}]}]}' > "$FH2/.codex/hooks.json"
HANDOFF_FAKE_HOME="$FH2" bash "$INSTALL" --yes --harness codex >/dev/null 2>&1
merged=$(cat "$FH2/.codex/hooks.json")
assert_contains "$merged" "my-own-guard" "merge preserves user's pre-existing hook"
assert_contains "$merged" "handoff-loader.sh" "merge adds handoff hook"
assert_eq "$([ -f "$FH2/.codex/hooks.json.bak" ] && echo yes || echo no)" "yes" "pre-existing hooks.json backed up"

# gemini: merge into a populated settings.json must preserve unrelated settings
FH3=$(mktemp -d); mkdir -p "$FH3/.gemini"
printf '{"theme":"dark","model":"gemini-pro","hooks":{"BeforeTool":[{"type":"command","command":"user-scan"}]}}' > "$FH3/.gemini/settings.json"
HANDOFF_FAKE_HOME="$FH3" bash "$INSTALL" --yes --harness gemini >/dev/null 2>&1
gs=$(cat "$FH3/.gemini/settings.json")
assert_json_field "$gs" '.theme' "dark" "gemini merge preserves unrelated setting (theme)"
assert_json_field "$gs" '.hooks.BeforeTool[0].command' "user-scan" "gemini merge preserves user's other hook"
assert_contains "$gs" "handoff-loader.sh" "gemini merge adds SessionStart handoff hook"
assert_eq "$([ -f "$FH3/.gemini/settings.json.bak" ] && echo yes || echo no)" "yes" "gemini settings.json backed up"
finish
