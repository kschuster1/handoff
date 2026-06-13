#!/usr/bin/env bash
# The /handoff command body has one canonical source: core/handoff.md.
# Claude Code and Codex need REAL files (their loaders don't follow symlinks in the
# plugin/prompt cache), so commands/handoff.md and adapters/codex/prompts/handoff.md are
# copies. This test fails if any copy drifts from the canonical source — re-copy core/handoff.md
# over them when you change it.
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

# real files, not symlinks (Claude/Codex loaders skip symlinks)
assert_eq "$([ -L "$ROOT/commands/handoff.md" ] && echo link || echo file)" "file" "commands/handoff.md is a real file (not symlink)"
assert_eq "$([ -L "$ROOT/adapters/codex/prompts/handoff.md" ] && echo link || echo file)" "file" "codex prompt is a real file (not symlink)"

# copies identical to canonical core/handoff.md
if diff -q "$ROOT/core/handoff.md" "$ROOT/commands/handoff.md" >/dev/null; then
  assert_eq "insync" "insync" "commands/handoff.md matches core/handoff.md"
else
  assert_eq "drift" "insync" "commands/handoff.md matches core/handoff.md (re-copy core over it)"
fi
if diff -q "$ROOT/core/handoff.md" "$ROOT/adapters/codex/prompts/handoff.md" >/dev/null; then
  assert_eq "insync" "insync" "codex prompt matches core/handoff.md"
else
  assert_eq "drift" "insync" "codex prompt matches core/handoff.md (re-copy core over it)"
fi
finish
