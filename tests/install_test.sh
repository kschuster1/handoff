#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$ROOT/install.sh"

FH=$(mktemp -d)            # fake HOME
mkdir -p "$FH/.gemini"   # pretend gemini is installed; claude absent

HANDOFF_FAKE_HOME="$FH" bash "$INSTALL" --yes >/dev/null 2>&1

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

# gemini: merge into a populated settings.json must preserve unrelated settings
FH3=$(mktemp -d); mkdir -p "$FH3/.gemini"
printf '{"theme":"dark","model":"gemini-pro","hooks":{"BeforeTool":[{"type":"command","command":"user-scan"}]}}' > "$FH3/.gemini/settings.json"
HANDOFF_FAKE_HOME="$FH3" bash "$INSTALL" --yes --harness gemini >/dev/null 2>&1
gs=$(cat "$FH3/.gemini/settings.json")
assert_json_field "$gs" '.theme' "dark" "gemini merge preserves unrelated setting (theme)"
assert_json_field "$gs" '.hooks.BeforeTool[0].command' "user-scan" "gemini merge preserves user's other hook"
assert_contains "$gs" "handoff-loader.sh" "gemini merge adds SessionStart handoff hook"
assert_eq "$([ -f "$FH3/.gemini/settings.json.bak" ] && echo yes || echo no)" "yes" "gemini settings.json backed up"

# ── shipped Claude plugin claude.json: clear + compact snapshot wired, loader intact ──
ch=$(cat "$ROOT/hooks/claude.json")
assert_json_field "$ch" '.hooks.SessionEnd[0].hooks[0].command | contains("handoff-snapshot.sh")' "true" "claude plugin: SessionEnd snapshot present (covers /clear)"
assert_json_field "$ch" '.hooks.PreCompact[0].hooks[0].command | contains("handoff-snapshot.sh")' "true" "claude plugin: PreCompact snapshot present (covers /compact)"
assert_json_field "$ch" '.hooks.SessionStart[0].hooks[0].command | contains("handoff-loader.sh")' "true" "claude plugin: SessionStart loader intact"

# ── --autosave wires gemini AfterAgent snapshot ──
FH5=$(mktemp -d); mkdir -p "$FH5/.gemini"
HANDOFF_FAKE_HOME="$FH5" bash "$INSTALL" --yes --autosave --harness gemini >/dev/null 2>&1
gj=$(cat "$FH5/.gemini/settings.json")
assert_json_field "$gj" '[.hooks.AfterAgent[].command | select(contains("handoff-snapshot.sh"))] | length' "1" "autosave: gemini AfterAgent snapshot wired"
assert_json_field "$gj" '.hooks.SessionStart[0].command | contains("handoff-loader.sh")' "true" "autosave: gemini SessionStart loader intact alongside AfterAgent"

finish
