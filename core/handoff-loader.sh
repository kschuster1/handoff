#!/usr/bin/env bash
# handoff-loader.sh [claude|codex|gemini]
# Session-start loader. Emits handoff context. cwd source + output format depend on harness.
set -e

HARNESS="${1:-claude}"

# stdin JSON only for claude/codex (gemini passes cwd via env)
INPUT=""
if [ "$HARNESS" != "gemini" ]; then
  INPUT=$(cat 2>/dev/null || true)
fi

# ── resolve session cwd ──────────────────────────────────────
CWD=""
case "$HARNESS" in
  gemini) CWD="${GEMINI_CWD:-}";;
  *)      if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
            CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
          fi;;
esac
CWD="${CWD:-$PWD}"

HDIR="$CWD/.handoff"
HANDOFF="$HDIR/HANDOFF.md"
AUTOSAVE="$HDIR/AUTOSAVE.md"

# ── emit(): format the body for the active harness ───────────
emit() {
  local body; body=$(cat)
  if [ "$HARNESS" = "gemini" ]; then
    jq -n --arg c "$body" \
      '{hookSpecificOutput:{hookEventName:"BeforeAgent",additionalContext:$c}}'
  else
    printf '%s\n' "$body"
  fi
}

# ── build_body(): choose what to say ─────────────────────────
build_body() {
  # (HANDOFF + AUTOSAVE branches added in later tasks)
  cat <<EOF
═══ No handoff for this project ═══
Path checked: ${HANDOFF}
Use /handoff to create one when pausing work.
═══════════════════════════════════

[handoff-loader-instruction]
On your VERY FIRST response in this session, emit exactly this line at the top
(before any other output, before any tool calls), then proceed normally:

    ∅ No handoff available for this project

Do not skip. Do not paraphrase. Emit verbatim, once, then continue.
EOF
}

build_body | emit
