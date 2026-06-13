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

# gemini command + hooks placed, include resolved
gt=$(cat "$FH/.gemini/commands/handoff.toml" 2>/dev/null || echo "")
assert_contains "$gt" "@{$ROOT/core/handoff.md}" "gemini include resolved to abs path"

# claude not installed → skipped cleanly (no dir created)
assert_eq "$([ -d "$FH/.claude/plugins" ] && echo yes || echo no)" "no" "absent harness skipped"

# idempotency: second run does not duplicate or error
HANDOFF_FAKE_HOME="$FH" bash "$INSTALL" --yes >/dev/null 2>&1
assert_eq "$?" "0" "second install run is idempotent (exit 0)"
finish
