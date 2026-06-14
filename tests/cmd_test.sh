#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
CMD="$(dirname "$0")/../core/handoff.md"
body=$(cat "$CMD")

assert_contains "$body" ".handoff/HANDOFF.md" "uses neutral storage path"
assert_not_contains "$body" ".claude/HANDOFF.md" "no legacy .claude path remains"
assert_contains "$body" "interactive question tool" "harness-neutral question phrasing present"
assert_contains "$body" "git status --short" "keeps git-as-ground-truth pre-draft step"
assert_contains "$body" "[done]" "keeps state tags"
assert_contains "$body" "argument-hint" "has frontmatter argument-hint"
assert_contains "$body" "\$ARGUMENTS" "dispatches on \$ARGUMENTS"
finish
