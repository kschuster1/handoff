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
no_handoff_body() {
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

resume_flow_instruction() { # confirm_line  resume_display
  cat <<EOF

[handoff-loader-instruction]
On your VERY FIRST response in this session, do exactly these steps in order:

1. Emit this confirmation line at the very top, verbatim, no tool calls before it:

       ${1}

2. Show the resume preview as a single line:

       Next up: ${2}

3. Ask the user: "Resume that, or do something else?"
   If an interactive question tool (e.g. AskUserQuestion) is available, use it with options:
       - "Resume — ${2}" (mark Recommended)
       - "Pick a different item from the Next list"
       - "Something else"
   Otherwise ask inline as a numbered list and wait for the user's choice.
   Then act on the answer.

EXCEPTION: if the user's first message is itself a clear, specific instruction
(e.g. "fix the bug in foo.ts", "deploy to prod"), skip step 3, emit only steps
1 + 2 as a brief preamble, and execute the request.
"hi", ".", "?", "where were we", "continue", "resume" → run all 3 steps.
EOF
}

build_body() {
  if [ ! -f "$HANDOFF" ]; then
    no_handoff_body; return
  fi

  # frontmatter (between first two `---` lines)
  local fm summary resume inject
  fm=$(awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "$HANDOFF")
  summary=$(printf '%s\n' "$fm" | grep -E '^summary:' | head -1 | sed 's/^summary: *//')
  resume=$(printf '%s\n' "$fm"  | grep -E '^resume:'  | head -1 | sed 's/^resume: *//')
  inject=$(printf '%s\n' "$fm"  | grep -E '^inject:'  | head -1 | sed 's/^inject: *//' | tr -d ' ')

  local now mtime age
  now=$(date +%s)
  mtime=$(stat -c %Y "$HANDOFF" 2>/dev/null || stat -f %m "$HANDOFF" 2>/dev/null || echo "$now")
  age=$((now - mtime))

  local rel
  if   [ $age -lt 3600 ];   then rel="$((age/60))m ago"
  elif [ $age -lt 86400 ];  then rel="$((age/3600))h ago"
  elif [ $age -lt 604800 ]; then rel="$((age/86400))d ago"
  else                           rel="$((age/604800))w ago"; fi

  local chars tokens
  chars=$(wc -c < "$HANDOFF" | tr -d ' ')
  tokens=$((chars / 4))

  local mode="pointer"
  if   [ "$inject" = "full" ];   then mode="full"
  elif [ "$inject" = "pointer" ]; then mode="pointer"
  elif [ $age -lt 86400 ] && [ $chars -lt 8192 ]; then mode="full"; fi

  local stale=""
  [ $age -gt 604800 ] && stale=" ⚠ STALE (>7d, may be outdated — verify before trusting)"

  local resume_display="${resume:-<no resume field — see Next section>}"
  local confirm

  if [ "$mode" = "full" ]; then
    printf '═══ HANDOFF.md (auto-loaded, fresh %s, ~%s tokens) ═══\n' "$rel" "$tokens"
    printf 'Source: .handoff/HANDOFF.md\n'
    printf 'If current task does NOT match this handoff, treat as stale context — ignore and proceed.\n'
    printf -- '─────────────────────────────────────────────\n'
    cat "$HANDOFF"
    printf -- '─────────────────────────────────────────────\nEnd HANDOFF.md.\n'
    confirm="🤝 Handoff ingested — ~${tokens} tokens, ${rel} (full inject)"
  else
    printf '═══ HANDOFF.md detected ═══\n'
    printf 'Path: .handoff/HANDOFF.md (~%s tokens, updated %s%s)\n' "$tokens" "$rel" "$stale"
    printf 'Summary: %s\n' "${summary:-<no summary in frontmatter>}"
    printf 'Resume: %s\n' "$resume_display"
    printf 'Action: Read .handoff/HANDOFF.md if continuing prior work.\n'
    printf '═══════════════════════════\n'
    confirm="🤝 Handoff pointer loaded — ~${tokens} tokens, ${rel} (read file to resume)"
  fi

  resume_flow_instruction "$confirm" "$resume_display"
}

build_body | emit
