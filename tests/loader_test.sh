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

# ---------- handoff present ----------
mkfix() { # dir summary resume body  -> writes .handoff/HANDOFF.md
  mkdir -p "$1/.handoff"
  { printf -- '---\nupdated: 2026-06-13T00:00:00Z\nsummary: %s\nresume: %s\n---\n\n# Handoff\n\n%s\n' \
      "$2" "$3" "$4"; } > "$1/.handoff/HANDOFF.md"
}

D1=$(mktemp -d)
mkfix "$D1" "wiring loader" "finish task 3" "## Task\nbuild loader"
out=$(printf '{"cwd":"%s"}' "$D1" | bash "$LOADER" claude)
assert_contains "$out" "HANDOFF.md (auto-loaded" "fresh small → full inject header"
assert_contains "$out" "build loader" "full inject includes body text"
assert_contains "$out" "🤝 Handoff ingested" "full: confirmation line"
assert_contains "$out" "Next up: finish task 3" "full: resume preview from frontmatter"
assert_contains "$out" "Resume that, or do something else?" "full: resume question text"
assert_contains "$out" "AskUserQuestion" "neutral phrasing still names the tool as the preferred option"

# pointer via inject override
D2=$(mktemp -d); mkfix "$D2" "big task" "do the thing" "## Task\nx"
printf -- '---\nupdated: x\nsummary: big task\nresume: do the thing\ninject: pointer\n---\n\nbody\n' > "$D2/.handoff/HANDOFF.md"
out=$(printf '{"cwd":"%s"}' "$D2" | bash "$LOADER" claude)
assert_contains "$out" "HANDOFF.md detected" "inject:pointer → pointer header"
assert_contains "$out" "Summary: big task" "pointer shows summary"
assert_not_contains "$out" "═══ HANDOFF.md (auto-loaded" "pointer must not full-inject"

# stale (>7d) forces warning; touch mtime 8 days back
D3=$(mktemp -d); mkfix "$D3" "old" "resume old" "## Task\nold"
ts=$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)
touch -t "$ts" "$D3/.handoff/HANDOFF.md"
out=$(printf '{"cwd":"%s"}' "$D3" | bash "$LOADER" claude)
assert_contains "$out" "STALE" "old handoff → STALE warning"

# ---------- gemini full inject is valid JSON carrying the body ----------
DG=$(mktemp -d); mkfix "$DG" "gem task" "resume gem" '## Task\nline with "quotes" and\nnewlines'
out=$(GEMINI_CWD="$DG" bash "$LOADER" gemini </dev/null)
# must be parseable JSON
echo "$out" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "gemini full: output is valid JSON"
ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')
assert_contains "$ctx" "HANDOFF.md (auto-loaded" "gemini full: body inside additionalContext"
assert_contains "$ctx" 'with "quotes"' "gemini full: quotes preserved through JSON"

# ---------- AUTOSAVE precedence ----------
mkauto() { # dir branch dirty commits
  mkdir -p "$1/.handoff"
  printf -- '---\nbranch: %s\ndirty: %s\ncommits: %s\n---\n\n(git snapshot)\n' \
    "$2" "$3" "$4" > "$1/.handoff/AUTOSAVE.md"
}

# autosave only → pointer line
DA=$(mktemp -d); mkauto "$DA" "feature/x" "3" "2"
out=$(printf '{"cwd":"%s"}' "$DA" | bash "$LOADER" claude)
assert_contains "$out" "auto-snapshot" "autosave-only → snapshot pointer"
assert_contains "$out" "feature/x" "autosave pointer names branch"
assert_contains "$out" ".handoff/AUTOSAVE.md" "autosave pointer names file"
assert_not_contains "$out" "(git snapshot)" "autosave must NOT inject file body"

# both present → HANDOFF wins
DB=$(mktemp -d); mkfix "$DB" "manual" "resume manual" "## Task\nmanual body"
mkauto "$DB" "feature/y" "1" "0"
out=$(printf '{"cwd":"%s"}' "$DB" | bash "$LOADER" claude)
assert_contains "$out" "manual body" "both present → manual handoff wins"
assert_not_contains "$out" "auto-snapshot" "both present → no autosave pointer"

finish
