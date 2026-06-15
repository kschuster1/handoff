#!/usr/bin/env bash
# handoff-loader.sh [claude|codex|gemini]
# SessionStart loader for all three harnesses. They all deliver a stdin JSON payload
# with a `.cwd` field; only the OUTPUT format differs (gemini requires a JSON envelope).
set -e

HARNESS="${1:-claude}"

# All harnesses pass a stdin JSON payload at SessionStart; read it.
INPUT=$(cat 2>/dev/null || true)

# ── resolve session cwd (stdin JSON .cwd, then $PWD) ─────────
CWD=""
if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
fi
# legacy/fallback: honor $GEMINI_CWD if stdin gave us nothing
CWD="${CWD:-${GEMINI_CWD:-$PWD}}"

HDIR="$CWD/.handoff"
HANDOFF="$HDIR/HANDOFF.md"
AUTOSAVE="$HDIR/AUTOSAVE.md"

# ── one-time, silent, reversible legacy migration ────────────
ensure_handoff_gitignore() { # project_root
  local gi="$1/.gitignore"
  { [ -f "$gi" ] && grep -qxF '.handoff/' "$gi"; } || printf '.handoff/\n' >> "$gi" 2>/dev/null || true
}
strip_handoff_refs() { # memory_file
  local f="$1"
  [ -f "$f" ] || return 0
  grep -qE '\.ai/HANDOFF\.md|\.claude/HANDOFF\.md|handoff-pointer' "$f" 2>/dev/null || return 0
  cp "$f" "$f.bak" 2>/dev/null || return 0
  grep -vE '\.ai/HANDOFF\.md|\.claude/HANDOFF\.md|handoff-pointer' "$f.bak" > "$f" 2>/dev/null || cp "$f.bak" "$f" 2>/dev/null
}
migrate_legacy_handoff() { # project_root
  local root="$1" legacy="" cand
  [ -f "$root/.handoff/HANDOFF.md" ] && return 0
  for cand in "$root/.ai/HANDOFF.md" "$root/.claude/HANDOFF.md"; do
    [ -f "$cand" ] && { legacy="$cand"; break; }
  done
  [ -z "$legacy" ] && return 0
  mkdir -p "$root/.handoff" 2>/dev/null || return 0
  cp "$legacy" "$root/.handoff/HANDOFF.md" 2>/dev/null || return 0
  mv "$legacy" "$legacy.bak" 2>/dev/null || true
  ensure_handoff_gitignore "$root"
  strip_handoff_refs "$root/CLAUDE.md"
  strip_handoff_refs "$root/AGENTS.md"
}
# Run migration with errexit OFF so the internal `[ -f ] && ...` guards can't abort the loader.
set +e
migrate_legacy_handoff "$CWD"
set -e

# ── emit(): format the body for the active harness ───────────
# Gemini requires a structured JSON envelope. Claude and Codex take raw stdout as the
# SessionStart context. Codex ECHOES that context to the user verbatim (a transparency
# feature — there is no silent-inject), so the Codex body is deliberately terse (see
# codex_body); the JSON envelope only made the visible block longer, so it is not used here.
emit() {
  local body; body=$(cat)
  if [ "$HARNESS" = "gemini" ]; then
    if ! command -v jq >/dev/null 2>&1; then
      printf 'handoff-loader: jq is required for gemini mode\n' >&2
      return 0   # emit nothing → Gemini gets no malformed context
    fi
    jq -n --arg c "$body" \
      '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
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

autosave_body() {
  local fm branch dirty commits rel mtime now
  fm=$(awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "$AUTOSAVE")
  branch=$(printf '%s\n' "$fm"  | grep -E '^branch:'  | head -1 | sed 's/^branch: *//')
  dirty=$(printf '%s\n' "$fm"   | grep -E '^dirty:'   | head -1 | sed 's/^dirty: *//')
  commits=$(printf '%s\n' "$fm" | grep -E '^commits:' | head -1 | sed 's/^commits: *//')
  now=$(date +%s)
  mtime=$(stat -c %Y "$AUTOSAVE" 2>/dev/null || stat -f %m "$AUTOSAVE" 2>/dev/null || echo "$now")
  local amin=$(( (now-mtime)/60 )); [ $amin -lt 0 ] && amin=0
  rel="${amin}m ago"
  cat <<EOF
═══ Auto-snapshot present (no manual handoff) ═══
⚠ auto-snapshot: ${branch:-?}, ${dirty:-?} files dirty, ${commits:-?} commits — updated ${rel}
This is a mechanical git snapshot, not a written handoff.
Action: read .handoff/AUTOSAVE.md ONLY if resuming prior work. Otherwise ignore.
═══════════════════════════════════════════════

[handoff-loader-instruction]
On your VERY FIRST response, emit this line verbatim at the top, then continue:

    🤝 Auto-snapshot available — read .handoff/AUTOSAVE.md if resuming
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
    if [ -f "$AUTOSAVE" ]; then autosave_body; else no_handoff_body; fi
    return
  fi

  # frontmatter (between first two `---` lines)
  local fm summary resume inject
  fm=$(awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "$HANDOFF")
  summary=$(printf '%s\n' "$fm" | grep -E '^summary:' | head -1 | sed 's/^summary: *//')
  resume=$(printf '%s\n' "$fm"  | grep -E '^resume:'  | head -1 | sed 's/^resume: *//')
  # frontmatter values must be single-line (multi-line YAML scalars not supported)
  inject=$(printf '%s\n' "$fm"  | grep -E '^inject:'  | head -1 | sed 's/^inject: *//' | tr -d ' \t')

  local now mtime age
  now=$(date +%s)
  mtime=$(stat -c %Y "$HANDOFF" 2>/dev/null || stat -f %m "$HANDOFF" 2>/dev/null || echo "$now")
  age=$((now - mtime)); [ $age -lt 0 ] && age=0

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
    printf '═══ HANDOFF.md (auto-loaded, %s%s, ~%s tokens) ═══\n' "$rel" "$stale" "$tokens"
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

# ── codex_body(): terse output ───────────────────────────────
# Codex echoes the injected SessionStart context to the user verbatim, so keep it to ~2 lines.
# No full-file dump, no long instruction block — the model reads .handoff/HANDOFF.md if resuming.
codex_body() {
  if [ ! -f "$HANDOFF" ]; then
    [ -f "$AUTOSAVE" ] && printf '🤝 Auto-snapshot exists (.handoff/AUTOSAVE.md) — read it if resuming prior work.\n'
    return 0
  fi
  local fm summary resume
  fm=$(awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "$HANDOFF")
  summary=$(printf '%s\n' "$fm" | grep -E '^summary:' | head -1 | sed 's/^summary: *//')
  resume=$(printf '%s\n' "$fm"  | grep -E '^resume:'  | head -1 | sed 's/^resume: *//')
  printf '🤝 Saved handoff for this project (.handoff/HANDOFF.md) — Summary: %s | Resume: %s\n' \
    "${summary:-—}" "${resume:-see Next section}"
  printf 'If the user opens with a greeting or "resume"/"continue"/"where were we", offer to resume that; otherwise just proceed. Read the file for full detail.\n'
}

if [ "$HARNESS" = "codex" ]; then codex_body | emit; else build_body | emit; fi
