#!/usr/bin/env bash
# The /handoff command body has one canonical source: core/handoff.md.
# Claude Code needs a REAL file (its loader doesn't follow symlinks in the plugin cache),
# so commands/handoff.md is a copy. This test fails if the copy drifts from the canonical
# source — re-copy core/handoff.md over it when you change it.
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

# real file, not symlink (Claude loader skips symlinks)
assert_eq "$([ -L "$ROOT/commands/handoff.md" ] && echo link || echo file)" "file" "commands/handoff.md is a real file (not symlink)"

# copy identical to canonical core/handoff.md
if diff -q "$ROOT/core/handoff.md" "$ROOT/commands/handoff.md" >/dev/null; then
  assert_eq "insync" "insync" "commands/handoff.md matches core/handoff.md"
else
  assert_eq "drift" "insync" "commands/handoff.md matches core/handoff.md (re-copy core over it)"
fi
finish
