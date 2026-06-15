#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

run_loader() { # project_dir
  printf '{"cwd":"%s"}' "$1" | bash "$ROOT/core/handoff-loader.sh" claude >/dev/null 2>&1 || true
}

# --- migrates .ai/HANDOFF.md, strips stale CLAUDE.md ref, ignores .handoff/ ---
p=$(mktemp -d)
mkdir -p "$p/.ai"
printf -- '---\nsummary: legacy\nresume: do x\n---\n# Handoff\nold\n' > "$p/.ai/HANDOFF.md"
printf 'project notes\n<!-- handoff-pointer --> read .ai/HANDOFF.md first\nkeep me\n' > "$p/CLAUDE.md"
run_loader "$p"
assert_eq "$([ -f "$p/.handoff/HANDOFF.md" ] && echo y || echo n)" "y" "migrated to .handoff/HANDOFF.md"
assert_contains "$(cat "$p/.handoff/HANDOFF.md")" "summary: legacy" "migrated content preserved"
assert_eq "$([ -f "$p/.ai/HANDOFF.md.bak" ] && echo y || echo n)" "y" "legacy renamed to .bak"
assert_eq "$([ -f "$p/.ai/HANDOFF.md" ] && echo y || echo n)" "n" "legacy original removed"
assert_contains "$(cat "$p/.gitignore")" ".handoff/" ".handoff/ gitignored"
assert_not_contains "$(cat "$p/CLAUDE.md")" "handoff-pointer" "stale pointer line stripped"
assert_contains "$(cat "$p/CLAUDE.md")" "keep me" "non-handoff CLAUDE.md lines preserved"
assert_eq "$([ -f "$p/CLAUDE.md.bak" ] && echo y || echo n)" "y" "CLAUDE.md backed up before edit"
rm -rf "$p"

# --- does NOT fire when a current handoff already exists ---
q=$(mktemp -d)
mkdir -p "$q/.ai" "$q/.handoff"
printf 'legacy\n' > "$q/.ai/HANDOFF.md"
printf -- '---\nsummary: current\n---\n' > "$q/.handoff/HANDOFF.md"
run_loader "$q"
assert_contains "$(cat "$q/.handoff/HANDOFF.md")" "summary: current" "existing handoff untouched"
assert_eq "$([ -f "$q/.ai/HANDOFF.md.bak" ] && echo y || echo n)" "n" "no migration when current handoff exists"
rm -rf "$q"

# --- .claude/HANDOFF.md also migrates ---
r=$(mktemp -d)
mkdir -p "$r/.claude"
printf 'claudelegacy\n' > "$r/.claude/HANDOFF.md"
run_loader "$r"
assert_eq "$([ -f "$r/.handoff/HANDOFF.md" ] && echo y || echo n)" "y" ".claude/HANDOFF.md migrates too"
rm -rf "$r"
finish
