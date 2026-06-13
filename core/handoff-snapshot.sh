#!/usr/bin/env bash
# handoff-snapshot.sh [cwd]
# Mechanical, model-free safety net. Writes a size-capped .handoff/AUTOSAVE.md
# capturing git ground-truth. Self-gating; never clobbers a manual HANDOFF.md.
set -e

CWD="${1:-$PWD}"
cd "$CWD" 2>/dev/null || exit 0

# only meaningful inside a git work tree
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

HDIR="$CWD/.handoff"
# don't compete with a real handoff
if [ -f "$HDIR/HANDOFF.md" ]; then exit 0; fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
dirty=$(git status --short 2>/dev/null | wc -l | tr -d ' ')

# commits ahead of upstream (0 if no upstream)
if up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
  commits=$(git rev-list --count "${up}..HEAD" 2>/dev/null || echo 0)
else
  commits=0
fi

# self-gate: nothing worth capturing
if [ "$dirty" -eq 0 ] && [ "$commits" -eq 0 ]; then
  exit 0
fi

mkdir -p "$HDIR"
{
  printf -- '---\n'
  printf 'generated_by: handoff-snapshot.sh\n'
  printf 'branch: %s\n' "$branch"
  printf 'dirty: %s\n' "$dirty"
  printf 'commits: %s\n' "$commits"
  printf -- '---\n\n'
  printf '# Auto-snapshot (mechanical — no narrative)\n\n'
  printf 'Recent commits:\n```\n'
  git log --oneline -5 2>/dev/null
  printf '```\n\nWorking tree (diff --stat, capped):\n```\n'
  git diff --stat 2>/dev/null | head -20
  printf '```\n\nUntracked/changed files:\n```\n'
  git status --short 2>/dev/null | head -20
  printf '```\n'
} > "$HDIR/AUTOSAVE.md"

exit 0
