# Cross-Harness Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the Claude-Code-only `claude-handoff` plugin into a cross-harness tool whose handoff file is portable across Claude Code, Codex CLI, and Gemini CLI, with auto-load on session start and an opt-in mechanical auto-snapshot safety net.

**Architecture:** One source-of-truth shell loader (`core/handoff-loader.sh`) parameterized by a harness arg that selects cwd-source and output-format; one shared command body (`core/handoff.md`) consumed directly by Claude/Codex and `@{}`-included by Gemini; one shell snapshot script; thin per-harness adapter wiring; an `install.sh` plus documented manual steps. Handoffs live at a neutral `.handoff/HANDOFF.md`.

**Tech Stack:** Bash (POSIX-ish, macOS + Linux), `jq` (JSON parse/emit), Markdown, JSON, TOML. Tests are dependency-light bash scripts (require `jq`).

---

## File Structure

The repo root **is** the Claude Code plugin root (so it can be added directly as a marketplace). Other harnesses are wired by `install.sh` from `adapters/`.

```
handoff/                              ← repo root = Claude Code plugin root
├── .claude-plugin/plugin.json        # CC plugin manifest
├── marketplace.json                  # lets the repo be added as a CC marketplace
├── commands/handoff.md               # symlink → ../core/handoff.md  (CC slash command)
├── hooks/hooks.json                  # CC SessionStart → core/handoff-loader.sh claude
├── core/
│   ├── handoff-loader.sh             # parameterized loader (claude|codex|gemini)
│   ├── handoff-snapshot.sh           # opt-in mechanical snapshot → .handoff/AUTOSAVE.md
│   └── handoff.md                    # SINGLE SOURCE command body
├── adapters/
│   ├── codex/
│   │   ├── prompts/handoff.md        # symlink → ../../../core/handoff.md
│   │   └── hooks.json                # Codex SessionStart → handoff-loader.sh codex
│   └── gemini/
│       ├── commands/handoff.toml     # @{<abs>/core/handoff.md} + {{args}}
│       └── hooks.json                # Gemini BeforeAgent → handoff-loader.sh gemini
├── install.sh                        # detect harnesses, wire, --autosave opt-in, pointer
├── tests/
│   ├── lib.sh                        # tiny assert helpers + pass/fail tracking
│   ├── loader_test.sh                # drives handoff-loader.sh with synthetic inputs
│   └── snapshot_test.sh             # drives handoff-snapshot.sh in temp git repos
├── .gitignore
├── LICENSE
└── README.md
```

**Responsibilities:**
- `core/handoff-loader.sh` — read session cwd, decide full/pointer/autosave/none, format output per harness. No writes.
- `core/handoff-snapshot.sh` — shell-only git snapshot, size-capped, self-gating, never clobbers a manual handoff.
- `core/handoff.md` — the WRITE/CLEAR/STATUS/LIST/HELP prompt. Harness-neutral.
- `adapters/*` — only the divergent wiring per harness.
- `install.sh` — placement + opt-in autosave + memory-file pointer.

**Cross-cutting conventions used by every task:**
- Storage dir: `.handoff/` under the session cwd. Active: `HANDOFF.md`. Snapshot: `AUTOSAVE.md`. Archives: `archive-*.md` (ignored by loader).
- Loader arg: `claude` (default) | `codex` | `gemini`.
- Gemini output JSON shape: `{"hookSpecificOutput":{"hookEventName":"BeforeAgent","additionalContext":"<body>"}}`.

---

## Task 1: Repo skeleton + test harness

**Files:**
- Create: `.gitignore`, `LICENSE`, `tests/lib.sh`, `tests/run.sh`

- [ ] **Step 1: Write the failing test (test harness self-check)**

Create `tests/lib.sh`:

```bash
#!/usr/bin/env bash
# tiny assertion lib — source it, then call asserts; call finish at end.
PASS=0; FAIL=0
_red() { printf '\033[31m%s\033[0m\n' "$1"; }
_grn() { printf '\033[32m%s\033[0m\n' "$1"; }

assert_contains() { # haystack needle msg
  if printf '%s' "$1" | grep -qF -- "$2"; then PASS=$((PASS+1)); _grn "ok: $3";
  else FAIL=$((FAIL+1)); _red "FAIL: $3"; _red "  expected to contain: $2"; fi
}
assert_not_contains() { # haystack needle msg
  if printf '%s' "$1" | grep -qF -- "$2"; then FAIL=$((FAIL+1)); _red "FAIL: $3"; _red "  expected NOT to contain: $2";
  else PASS=$((PASS+1)); _grn "ok: $3"; fi
}
assert_eq() { # actual expected msg
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); _grn "ok: $3";
  else FAIL=$((FAIL+1)); _red "FAIL: $3"; _red "  got:[$1] want:[$2]"; fi
}
assert_json_field() { # json jq-path expected msg
  local got; got=$(printf '%s' "$1" | jq -r "$2" 2>/dev/null || echo "<jq-error>")
  assert_eq "$got" "$3" "$4"
}
finish() { printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]; }
```

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
# runs every *_test.sh in tests/, fails if any fails
set -e
cd "$(dirname "$0")"
rc=0
for t in ./*_test.sh; do
  [ -e "$t" ] || continue
  echo "=== $t ==="
  bash "$t" || rc=1
done
exit $rc
```

- [ ] **Step 2: Run it to verify the harness works**

Run: `bash -c 'source tests/lib.sh; assert_eq a a "selfcheck"; assert_contains "hello" "ell" "selfcheck2"; finish'`
Expected: prints two `ok:` lines and `2 passed, 0 failed`, exit 0.

- [ ] **Step 3: Create `.gitignore` and `LICENSE`**

`.gitignore`:

```
node_modules/
.DS_Store
*.log
```

`LICENSE` — MIT, copyright holder `Keith Schuster`:

```
MIT License

Copyright (c) 2026 Keith Schuster

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: Make scripts executable, commit**

```bash
chmod +x tests/run.sh
git add .gitignore LICENSE tests/lib.sh tests/run.sh
git commit -m "chore: repo skeleton + bash test harness"
```

---

## Task 2: Loader — cwd resolution + output format + no-handoff case

**Files:**
- Create: `core/handoff-loader.sh`
- Test: `tests/loader_test.sh`

This task builds the loader scaffold: arg parsing, cwd from stdin JSON (claude/codex) or `$GEMINI_CWD` (gemini), the `emit()` output formatter, and the no-handoff branch.

- [ ] **Step 1: Write the failing test**

Create `tests/loader_test.sh`:

```bash
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

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/loader_test.sh`
Expected: FAIL — loader file does not exist / no output.

- [ ] **Step 3: Write minimal implementation**

Create `core/handoff-loader.sh`:

```bash
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x core/handoff-loader.sh && bash tests/loader_test.sh`
Expected: `4 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/handoff-loader.sh tests/loader_test.sh
git commit -m "feat(loader): cwd resolution, per-harness output, no-handoff case"
```

---

## Task 3: Loader — handoff present (full vs pointer, freshness, stale, size cap)

**Files:**
- Modify: `core/handoff-loader.sh` (replace `build_body`)
- Test: `tests/loader_test.sh` (append cases)

Rules (ported from `claude-handoff`): parse frontmatter `summary`/`resume`/`inject`; age from mtime; `tokens = chars/4`; mode = `full` if `inject:full`, `pointer` if `inject:pointer`, else `full` when `age<24h AND chars<8192` else `pointer`; append ⚠ STALE when `age>7d`. Always append the resume-flow instruction with harness-neutral question phrasing.

- [ ] **Step 1: Write the failing test (append to `tests/loader_test.sh`, before `finish`)**

```bash
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
touch -d '8 days ago' "$D3/.handoff/HANDOFF.md" 2>/dev/null || touch -A -080000 "$D3/.handoff/HANDOFF.md" 2>/dev/null || true
out=$(printf '{"cwd":"%s"}' "$D3" | bash "$LOADER" claude)
assert_contains "$out" "STALE" "old handoff → STALE warning"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/loader_test.sh`
Expected: new assertions FAIL (build_body only emits no-handoff).

- [ ] **Step 3: Replace `build_body` in `core/handoff-loader.sh`**

Replace the entire `build_body()` function with:

```bash
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
```

Then add these two helper functions just above `build_body()`:

```bash
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
```

Note: delete the old inline `build_body` heredoc body — the no-handoff text now lives in `no_handoff_body()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/loader_test.sh`
Expected: all assertions pass (count increased), exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/handoff-loader.sh tests/loader_test.sh
git commit -m "feat(loader): full/pointer modes, freshness gating, stale warning"
```

---

## Task 4: Loader — Gemini JSON output verified end-to-end

**Files:**
- Test: `tests/loader_test.sh` (append)

The `emit()` function from Task 2 already wraps gemini output in JSON. This task adds a regression test proving a *full* handoff body survives JSON-encoding intact (newlines/quotes), since that is the risky case.

- [ ] **Step 1: Write the failing test (append before `finish`)**

```bash
# ---------- gemini full inject is valid JSON carrying the body ----------
DG=$(mktemp -d); mkfix "$DG" "gem task" "resume gem" '## Task\nline with "quotes" and\nnewlines'
out=$(GEMINI_CWD="$DG" bash "$LOADER" gemini </dev/null)
# must be parseable JSON
echo "$out" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "gemini full: output is valid JSON"
ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')
assert_contains "$ctx" "HANDOFF.md (auto-loaded" "gemini full: body inside additionalContext"
assert_contains "$ctx" 'with "quotes"' "gemini full: quotes preserved through JSON"
```

- [ ] **Step 2: Run test to verify it passes (emit already handles it)**

Run: `bash tests/loader_test.sh`
Expected: PASS. If it FAILS on the quotes assertion, the bug is in `emit()` — confirm it uses `jq -n --arg` (not string interpolation). It does, so this should pass first try; the test locks it against regressions.

- [ ] **Step 3: Edge guard — gemini without jq**

Add this guard near the top of `emit()` so a missing `jq` fails loudly instead of emitting invalid JSON. Replace the `if [ "$HARNESS" = "gemini" ]; then` block in `emit()` with:

```bash
  if [ "$HARNESS" = "gemini" ]; then
    if ! command -v jq >/dev/null 2>&1; then
      printf 'handoff-loader: jq is required for gemini mode\n' >&2
      return 0   # emit nothing → Gemini gets no malformed context
    fi
    jq -n --arg c "$body" \
      '{hookSpecificOutput:{hookEventName:"BeforeAgent",additionalContext:$c}}'
  else
```

- [ ] **Step 4: Run test again**

Run: `bash tests/loader_test.sh`
Expected: still all pass.

- [ ] **Step 5: Commit**

```bash
git add core/handoff-loader.sh tests/loader_test.sh
git commit -m "test(loader): lock gemini JSON encoding; guard missing jq"
```

---

## Task 5: Loader — AUTOSAVE precedence (pointer-only fallback)

**Files:**
- Modify: `core/handoff-loader.sh` (`build_body` no-handoff branch)
- Test: `tests/loader_test.sh` (append)

When no manual `HANDOFF.md` exists but `AUTOSAVE.md` does, emit a single pointer line (never full). When both exist, `HANDOFF.md` wins.

- [ ] **Step 1: Write the failing test (append before `finish`)**

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/loader_test.sh`
Expected: autosave assertions FAIL (no-handoff branch ignores AUTOSAVE).

- [ ] **Step 3: Update the no-handoff branch in `build_body`**

In `build_body()`, replace the line:

```bash
  if [ ! -f "$HANDOFF" ]; then
    no_handoff_body; return
  fi
```

with:

```bash
  if [ ! -f "$HANDOFF" ]; then
    if [ -f "$AUTOSAVE" ]; then autosave_body; else no_handoff_body; fi
    return
  fi
```

Add this helper next to `no_handoff_body()`:

```bash
autosave_body() {
  local fm branch dirty commits rel mtime now
  fm=$(awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "$AUTOSAVE")
  branch=$(printf '%s\n' "$fm"  | grep -E '^branch:'  | head -1 | sed 's/^branch: *//')
  dirty=$(printf '%s\n' "$fm"   | grep -E '^dirty:'   | head -1 | sed 's/^dirty: *//')
  commits=$(printf '%s\n' "$fm" | grep -E '^commits:' | head -1 | sed 's/^commits: *//')
  now=$(date +%s)
  mtime=$(stat -c %Y "$AUTOSAVE" 2>/dev/null || stat -f %m "$AUTOSAVE" 2>/dev/null || echo "$now")
  rel="$(( (now-mtime)/60 ))m ago"
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/loader_test.sh`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add core/handoff-loader.sh tests/loader_test.sh
git commit -m "feat(loader): AUTOSAVE pointer fallback with HANDOFF precedence"
```

---

## Task 6: Mechanical auto-snapshot script

**Files:**
- Create: `core/handoff-snapshot.sh`
- Test: `tests/snapshot_test.sh`

Shell-only. Writes `.handoff/AUTOSAVE.md` with frontmatter (`branch`/`dirty`/`commits`) + a size-capped git body. Self-gates: no-op when tree is clean AND zero commits-ahead. Never writes if a manual `HANDOFF.md` already exists (don't compete with the good handoff). Accepts optional `$1` = target cwd (defaults `$PWD`) so hooks can pass it.

- [ ] **Step 1: Write the failing test**

Create `tests/snapshot_test.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
SNAP="$(dirname "$0")/../core/handoff-snapshot.sh"

newrepo() { # -> echoes path to a fresh git repo
  local d; d=$(mktemp -d)
  ( cd "$d" && git init -q && git config user.email t@t.t && git config user.name t \
      && echo hi > a.txt && git add a.txt && git commit -qm init ) >/dev/null
  echo "$d"
}

# clean tree, no commits ahead → no snapshot written
R1=$(newrepo)
bash "$SNAP" "$R1"
assert_eq "$([ -f "$R1/.handoff/AUTOSAVE.md" ] && echo yes || echo no)" "no" "clean repo → no snapshot"

# dirty tree → snapshot written with frontmatter
R2=$(newrepo)
( cd "$R2" && echo change >> a.txt && echo new > b.txt )
bash "$SNAP" "$R2"
assert_eq "$([ -f "$R2/.handoff/AUTOSAVE.md" ] && echo yes || echo no)" "yes" "dirty repo → snapshot written"
body=$(cat "$R2/.handoff/AUTOSAVE.md")
assert_contains "$body" "branch:" "snapshot has branch frontmatter"
assert_contains "$body" "dirty:" "snapshot has dirty count"
assert_contains "$body" "commits:" "snapshot has commits-ahead count"
# size cap: under 8KB comfortably
sz=$(wc -c < "$R2/.handoff/AUTOSAVE.md" | tr -d ' ')
assert_eq "$([ "$sz" -lt 8192 ] && echo ok || echo big)" "ok" "snapshot under 8KB"

# never clobbers a manual handoff
R3=$(newrepo)
( cd "$R3" && echo change >> a.txt )
mkdir -p "$R3/.handoff"; echo "MANUAL" > "$R3/.handoff/HANDOFF.md"
bash "$SNAP" "$R3"
assert_eq "$([ -f "$R3/.handoff/AUTOSAVE.md" ] && echo yes || echo no)" "no" "manual handoff present → snapshot skipped"

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/snapshot_test.sh`
Expected: FAIL — script missing.

- [ ] **Step 3: Write minimal implementation**

Create `core/handoff-snapshot.sh`:

```bash
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
[ -f "$HDIR/HANDOFF.md" ] && exit 0

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x core/handoff-snapshot.sh && bash tests/snapshot_test.sh`
Expected: all pass, exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/handoff-snapshot.sh tests/snapshot_test.sh
git commit -m "feat(snapshot): mechanical git auto-snapshot, self-gating, no-clobber"
```

---

## Task 7: Shared command body (`core/handoff.md`)

**Files:**
- Create: `core/handoff.md`
- Test: `tests/cmd_test.sh`

Port `claude-handoff/commands/handoff.md` with the neutralizations from the spec: storage path `.handoff/HANDOFF.md`, harness-neutral interactive-question phrasing, keep all accuracy guards.

- [ ] **Step 1: Write the failing test**

Create `tests/cmd_test.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
CMD="$(dirname "$0")/../core/handoff.md"
body=$(cat "$CMD")

assert_contains "$body" ".handoff/HANDOFF.md" "uses neutral storage path"
assert_not_contains "$body" ".claude/HANDOFF.md" "no legacy .claude path remains"
assert_contains "$body" "If an interactive question tool" "harness-neutral question phrasing present"
assert_contains "$body" "git status --short" "keeps git-as-ground-truth pre-draft step"
assert_contains "$body" "[done]" "keeps state tags"
assert_contains "$body" "argument-hint" "has frontmatter argument-hint"
assert_contains "$body" "\$ARGUMENTS" "dispatches on \$ARGUMENTS"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/cmd_test.sh`
Expected: FAIL — file missing.

- [ ] **Step 3: Write `core/handoff.md`**

Create the file with this exact content (frontmatter + body). It is the original command with `.claude/`→`.handoff/` and neutralized question phrasing:

````markdown
---
description: Manage .handoff/HANDOFF.md — write/update (default), clear, status, list, help
argument-hint: "[clear|status|list|help]"
---

# /handoff — Context handoff manager

Subcommand argument received: **$ARGUMENTS**

## Interactive questions (harness-neutral)

Whenever this command says "ask the user": If an interactive question tool
(e.g. AskUserQuestion) is available, use it. Otherwise present the options as a
numbered list in plain text and wait for the user's reply before proceeding.

## Dispatch

Inspect `$ARGUMENTS` (case-insensitive, trimmed) and run the matching flow.

| Argument | Flow | Effect |
|----------|------|--------|
| empty / none | WRITE (default) | Draft + confirm + write `.handoff/HANDOFF.md` |
| `clear` | CLEAR | Archive or delete `.handoff/HANDOFF.md` |
| `status` | STATUS | Show current handoff preview (read-only) |
| `list` | LIST | List active + archived handoffs |
| `help` | HELP | Show subcommand menu |
| anything else | HELP + warn unknown | `Unknown subcommand: <x>. Showing help…` |

---

## HELP flow

Output exactly:

```
/handoff — Context handoff manager

  /handoff              Write or update .handoff/HANDOFF.md (default)
  /handoff clear        Archive or delete .handoff/HANDOFF.md
  /handoff status       Show current handoff preview (read-only)
  /handoff list         List active + archived handoffs in .handoff/
  /handoff help         This menu

Loader hook auto-injects HANDOFF.md at session start (full <24h, pointer 24h-7d, STALE >7d).
Use /handoff before pausing work, /handoff status to peek, /handoff clear when done.
```

Then stop.

---

## STATUS flow

1. Check `./.handoff/HANDOFF.md`. If absent, output `∅ No HANDOFF.md in this project at ./.handoff/HANDOFF.md` and stop.
2. Read frontmatter. Display preview (no edits, no questions):
   ```
   HANDOFF.md
   ─────────────────
   Path:    .handoff/HANDOFF.md
   Updated: <relative>
   Tokens:  ~<n>
   Summary: <text>
   Resume:  <text or "—">
   ─────────────────
   ```
3. Stop.

---

## LIST flow

Run `ls -lat ./.handoff/HANDOFF*.md 2>/dev/null` (Bash). Output:

```
Handoffs in this project:

  ACTIVE:
    HANDOFF.md                              <relative time>

  ARCHIVES:
    archive-2026-05-10-143022.md            <relative time>
```

Omit empty sections. If neither active nor archives: `∅ No handoff files in .handoff/`. Stop.

---

## CLEAR flow

1. Check `./.handoff/HANDOFF.md`. If absent: `∅ No HANDOFF.md to clear at ./.handoff/HANDOFF.md` and stop.
2. Read file. Display preview (same format as STATUS).
3. Ask the user (three options):
   - Archive (Recommended) — rename to `.handoff/archive-YYYY-MM-DD-HHMMSS.md`. Loader ignores archives.
   - Delete permanently — `rm` the file. Recoverable only via git if tracked.
   - Cancel — no change.
4. Execute:
   - Archive → `mv ./.handoff/HANDOFF.md ./.handoff/archive-$(date -u +%Y-%m-%d-%H%M%S).md`. Confirm new path.
   - Delete → `rm ./.handoff/HANDOFF.md`. Confirm removed.
   - Cancel → `Cancelled. HANDOFF.md unchanged.`
5. After clear, suggest `/handoff` to write fresh, or leave clean if done.

### Safety rules
- Never silent-delete. Always preview + confirm.
- Default to Archive (loss-resistant).
- Never bulk-clean archives.

---

## WRITE flow (default)

Generate or update `./.handoff/HANDOFF.md` so the next session resumes cleanly.

### 1. Locate target
- Ensure `./.handoff/` exists (create if missing).
- Target: `./.handoff/HANDOFF.md`. If it exists, Read first — update, don't blind-overwrite.

### 2. Pre-draft verification (REQUIRED — do not skip)

Run and capture. Build State from this evidence, NOT transcript impressions.

```bash
git status --short
git diff --stat
git log --oneline -10
git diff --cached --stat
```

If not a git repo: `find . -type f -mtime -1 -not -path './node_modules/*' -not -path './.git/*' | head -20`.

Anything claimed `[done]` must appear in commits or `git diff --stat`. Anything in `git status` but uncommitted = `[wip]`.

### 3. Draft using strict template

```markdown
---
updated: <ISO 8601 UTC>
summary: <one line, <100 chars — current state for quick scan>
resume: <one line, <80 chars — concrete first action when resuming>
inject: <optional: "full" or "pointer" to override loader auto-decision>
---

# Handoff

## Task
<2-3 lines: what + why.>

## State
- [done] <thing> — evidence: `commit abc1234` or `path/to/file.ts:42`
- [wip] <thing> — evidence: shows in `git status`, not committed
- [planned] <thing> — NOT started, just intended

## Files
- `path/to/file.ts:42` — <one-line note>

## Decisions
- [locked] <choice> — rationale (must have code/commit backing)
- [tentative] <choice> — rationale (no code yet)

## Blockers
- <thing> — verbatim error: `EXACT_ERROR_TEXT`

## Next
1. <concrete step>
2. <concrete step>
```

### 4. Accuracy rules (HARD)
- `resume:` field required. Matches Next #1, paraphrased to one imperative line.
- Every State bullet tagged `[done]`/`[wip]`/`[planned]`. No untagged items.
- Evidence required for `[done]` — commit hash or file:line, else demote to `[wip]`.
- Decisions tagged. `[locked]` only if backed by committed code, else `[tentative]`.
- Errors verbatim, in backticks. Never paraphrase.
- No aspirational claims — discussed-but-not-built goes under Next.

### 5. Per-item confirmation

Before writing, present the draft. For ambiguous items, ask the user: "Item: `<text>` — keep as [done] / change to [wip] / drop?". Cap 4 items per question. Skip only for items with a committed hash that exists in `git log`.

### 6. Final confirm + write

Show full draft. Ask the user: "Write to `.handoff/HANDOFF.md`? [Yes / Edit section / Cancel]"
- Yes → Write file.
- Edit section → ask which, revise, re-confirm.
- Cancel → discard.

### 7. Token budget

Target <600 tokens (~2400 chars). Hard cap 2000 tokens (~8000 chars) — beyond it the loader forces pointer mode. Compress aggressively if exceeding.

### Edge cases
- Task fully complete → ask: "Task appears done. Run /handoff clear instead of writing stale resume state?"
- Pivoting to unrelated work → ask: "Unrelated to existing HANDOFF.md. Replace, append a section, or leave alone?"
- No git history → use `find -mtime -1`; flag evidence is filesystem-only.

### Why these rules exist
- Aspirational `[done]` items = #1 handoff failure mode.
- Verbatim errors preserve debug grep-ability.
- Tentative-as-locked decisions make the next session skip still-open choices.
- Git as ground truth removes "I think we did X" guesswork.
````

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/cmd_test.sh`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add core/handoff.md tests/cmd_test.sh
git commit -m "feat(core): harness-neutral /handoff command body"
```

---

## Task 8: Claude Code adapter (repo root = plugin root)

**Files:**
- Create: `.claude-plugin/plugin.json`, `marketplace.json`, `hooks/hooks.json`
- Create symlink: `commands/handoff.md` → `../core/handoff.md`
- Test: `tests/adapter_claude_test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/adapter_claude_test.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

# plugin.json valid + named handoff
pj=$(cat "$ROOT/.claude-plugin/plugin.json")
assert_json_field "$pj" '.name' "handoff" "plugin.json name"
echo "$pj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "plugin.json is valid JSON"

# marketplace.json lists the plugin
mp=$(cat "$ROOT/marketplace.json")
echo "$mp" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "marketplace.json is valid JSON"
assert_contains "$mp" "handoff" "marketplace lists handoff"

# hooks.json: SessionStart → loader with claude arg, uses plugin root var
hj=$(cat "$ROOT/hooks/hooks.json")
echo "$hj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "hooks.json is valid JSON"
assert_contains "$hj" "SessionStart" "hooks.json registers SessionStart"
assert_contains "$hj" "handoff-loader.sh" "hooks.json calls the loader"
assert_contains "$hj" "claude" "hooks.json passes claude arg"
assert_contains "$hj" "CLAUDE_PLUGIN_ROOT" "hooks.json resolves via plugin root"

# command is the shared body (symlink resolves to same content)
assert_contains "$(cat "$ROOT/commands/handoff.md")" ".handoff/HANDOFF.md" "command symlink resolves to shared body"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/adapter_claude_test.sh`
Expected: FAIL — files missing.

- [ ] **Step 3: Create the adapter files**

`.claude-plugin/plugin.json`:

```json
{
  "name": "handoff",
  "version": "0.2.0",
  "description": "Cross-harness per-project context handoff: write .handoff/HANDOFF.md when pausing, auto-load on session start so the next session (in any supported harness) resumes cleanly.",
  "author": { "name": "Keith Schuster", "email": "keithschuster@gmail.com" },
  "license": "MIT",
  "keywords": ["handoff", "context", "session", "resume", "codex", "gemini", "cross-harness"]
}
```

`marketplace.json`:

```json
{
  "name": "claude-toolkit",
  "plugins": [
    {
      "name": "handoff",
      "source": "./",
      "description": "Cross-harness context handoff (Claude Code, Codex, Gemini)."
    }
  ]
}
```

`hooks/hooks.json`:

```json
{
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/core/handoff-loader.sh\" claude",
          "timeout": 5
        }
      ]
    }
  ]
}
```

Create the command symlink:

```bash
mkdir -p commands
ln -s ../core/handoff.md commands/handoff.md
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/adapter_claude_test.sh`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json marketplace.json hooks/hooks.json commands/handoff.md tests/adapter_claude_test.sh
git commit -m "feat(claude): plugin manifest, marketplace, SessionStart hook, command symlink"
```

---

## Task 9: Codex adapter

**Files:**
- Create: `adapters/codex/hooks.json`
- Create symlink: `adapters/codex/prompts/handoff.md` → `../../../core/handoff.md`
- Test: `tests/adapter_codex_test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/adapter_codex_test.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

hj=$(cat "$ROOT/adapters/codex/hooks.json")
echo "$hj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "codex hooks.json valid JSON"
assert_contains "$hj" "SessionStart" "codex registers SessionStart"
assert_contains "$hj" "handoff-loader.sh" "codex calls loader"
assert_contains "$hj" "codex" "codex passes codex arg"

assert_contains "$(cat "$ROOT/adapters/codex/prompts/handoff.md")" ".handoff/HANDOFF.md" "codex prompt symlink resolves to shared body"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/adapter_codex_test.sh`
Expected: FAIL.

- [ ] **Step 3: Create the files**

`adapters/codex/hooks.json` (the `{{HANDOFF_ROOT}}` placeholder is replaced by `install.sh` with the absolute repo path; manual installers edit it themselves — documented in README):

```json
{
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash \"{{HANDOFF_ROOT}}/core/handoff-loader.sh\" codex",
          "timeout": 5
        }
      ]
    }
  ]
}
```

Create the prompt symlink:

```bash
mkdir -p adapters/codex/prompts
ln -s ../../../core/handoff.md adapters/codex/prompts/handoff.md
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/adapter_codex_test.sh`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add adapters/codex/hooks.json adapters/codex/prompts/handoff.md tests/adapter_codex_test.sh
git commit -m "feat(codex): SessionStart hook + prompt symlink to shared body"
```

---

## Task 10: Gemini adapter

**Files:**
- Create: `adapters/gemini/commands/handoff.toml`, `adapters/gemini/hooks.json`
- Test: `tests/adapter_gemini_test.sh`

Gemini commands are TOML and can't symlink the markdown directly — they `@{}`-include it. The `{{HANDOFF_ROOT}}` placeholder is resolved to an absolute path by `install.sh`.

- [ ] **Step 1: Write the failing test**

Create `tests/adapter_gemini_test.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

toml=$(cat "$ROOT/adapters/gemini/commands/handoff.toml")
assert_contains "$toml" "description" "gemini toml has description"
assert_contains "$toml" "prompt" "gemini toml has prompt"
assert_contains "$toml" "@{" "gemini toml @{}-includes the shared body"
assert_contains "$toml" "core/handoff.md" "gemini include points at shared body"
assert_contains "$toml" "{{args}}" "gemini toml forwards args"

hj=$(cat "$ROOT/adapters/gemini/hooks.json")
echo "$hj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "gemini hooks.json valid JSON"
assert_contains "$hj" "BeforeAgent" "gemini uses BeforeAgent event"
assert_contains "$hj" "handoff-loader.sh" "gemini calls loader"
assert_contains "$hj" "gemini" "gemini passes gemini arg"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/adapter_gemini_test.sh`
Expected: FAIL.

- [ ] **Step 3: Create the files**

`adapters/gemini/commands/handoff.toml`:

```toml
description = "Manage .handoff/HANDOFF.md — write/update (default), clear, status, list, help"

prompt = """
@{{{HANDOFF_ROOT}}/core/handoff.md}

Subcommand argument: {{args}}
"""
```

`adapters/gemini/hooks.json`:

```json
{
  "BeforeAgent": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash \"{{HANDOFF_ROOT}}/core/handoff-loader.sh\" gemini",
          "timeout": 5
        }
      ]
    }
  ]
}
```

Note for implementer: in the TOML, `@{{{HANDOFF_ROOT}}/core/handoff.md}` is intentional — `{{HANDOFF_ROOT}}` is the installer placeholder, wrapped by Gemini's `@{...}` file-include delimiters, yielding `@{/abs/path/core/handoff.md}` after substitution.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/adapter_gemini_test.sh`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add adapters/gemini/commands/handoff.toml adapters/gemini/hooks.json tests/adapter_gemini_test.sh
git commit -m "feat(gemini): TOML command with @{} include + BeforeAgent hook"
```

---

## Task 11: Installer

**Files:**
- Create: `install.sh`
- Test: `tests/install_test.sh`

`install.sh` detects each harness home, wires its adapter, resolves `{{HANDOFF_ROOT}}` to the repo's absolute path, optionally enables autosave (`--autosave`), and optionally adds the memory-file pointer (`--pointer`). Honors `HANDOFF_FAKE_HOME` for testing and `--harness <name>` to limit scope.

- [ ] **Step 1: Write the failing test**

Create `tests/install_test.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/install_test.sh`
Expected: FAIL — installer missing.

- [ ] **Step 3: Write `install.sh`**

```bash
#!/usr/bin/env bash
# install.sh — wire the handoff tool into detected harnesses.
# Flags: --yes (no prompts), --autosave (add snapshot hooks), --pointer (add memory-file note),
#        --harness <claude|codex|gemini> (limit scope; repeatable).
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="${HANDOFF_FAKE_HOME:-$HOME}"
YES=0; AUTOSAVE=0; POINTER=0; ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1;;
    --autosave) AUTOSAVE=1;;
    --pointer) POINTER=1;;
    --harness) shift; ONLY="$ONLY $1";;
    *) echo "unknown flag: $1" >&2; exit 2;;
  esac
  shift
done

want() { # harness name → 0 if should install
  [ -z "$ONLY" ] && return 0
  printf '%s' "$ONLY" | grep -qw "$1"
}

# resolve {{HANDOFF_ROOT}} in a template file → stdout
render() { sed "s#{{HANDOFF_ROOT}}#${ROOT}#g" "$1"; }

log() { printf '  %s\n' "$1"; }

# ── Codex ────────────────────────────────────────────────────
if want codex && [ -d "$HOME_DIR/.codex" ]; then
  echo "Codex detected → $HOME_DIR/.codex"
  mkdir -p "$HOME_DIR/.codex/prompts"
  cp "$ROOT/core/handoff.md" "$HOME_DIR/.codex/prompts/handoff.md"
  render "$ROOT/adapters/codex/hooks.json" > "$HOME_DIR/.codex/hooks.json"
  log "prompt + SessionStart hook installed"
fi

# ── Gemini ───────────────────────────────────────────────────
if want gemini && [ -d "$HOME_DIR/.gemini" ]; then
  echo "Gemini detected → $HOME_DIR/.gemini"
  mkdir -p "$HOME_DIR/.gemini/commands"
  render "$ROOT/adapters/gemini/commands/handoff.toml" > "$HOME_DIR/.gemini/commands/handoff.toml"
  render "$ROOT/adapters/gemini/hooks.json" > "$HOME_DIR/.gemini/hooks.json"
  log "command + BeforeAgent hook installed"
fi

# ── Claude Code ──────────────────────────────────────────────
# Claude is normally installed via the plugin marketplace, not this script.
# We only print guidance unless the user clearly uses ~/.claude.
if want claude && [ -d "$HOME_DIR/.claude" ]; then
  echo "Claude Code detected → install via marketplace for the managed path:"
  log "/plugin marketplace add $ROOT"
  log "/plugin install handoff@claude-toolkit"
fi

# ── Optional: autosave hooks (append to each installed harness) ──
if [ "$AUTOSAVE" -eq 1 ]; then
  echo "Autosave: add snapshot hooks manually per the README (events differ per harness):"
  log "Claude/Codex: PreCompact + Stop → bash $ROOT/core/handoff-snapshot.sh"
  log "Gemini: AfterAgent → bash $ROOT/core/handoff-snapshot.sh"
fi

# ── Optional: memory-file pointer ────────────────────────────
if [ "$POINTER" -eq 1 ]; then
  MARK="<!-- handoff-pointer -->"
  NOTE="$MARK If .handoff/HANDOFF.md exists, read it at session start before responding."
  for mf in "$HOME_DIR/.codex/AGENTS.md" "$HOME_DIR/.gemini/GEMINI.md" "$HOME_DIR/.claude/CLAUDE.md"; do
    [ -d "$(dirname "$mf")" ] || continue
    if [ -f "$mf" ] && grep -qF "$MARK" "$mf"; then continue; fi
    printf '\n%s\n' "$NOTE" >> "$mf"
    log "pointer added to $mf"
  done
fi

echo "Done."
```

Note: this installer keeps autosave as printed guidance rather than auto-editing hook files, because each harness stores hooks differently and silently mutating a user's `hooks.json` to add events is riskier than the SessionStart wiring (which is a fresh file we own). The README documents the exact blocks.

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x install.sh && bash tests/install_test.sh`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/install_test.sh
git commit -m "feat(install): detect harnesses, wire adapters, resolve paths, optional pointer"
```

---

## Task 12: README + full suite green

**Files:**
- Create: `README.md`
- Run: `tests/run.sh` (all suites)

- [ ] **Step 1: Write `README.md`**

Create `README.md` covering: what it is; supported harnesses + capability matrix; install (marketplace for Claude, `install.sh` for Codex/Gemini, manual fallback per harness); storage path `.handoff/HANDOFF.md`; the autosave opt-in with the exact hook blocks per harness; commit-or-ignore guidance (port the trade-offs + symlink sync recipe from the original `claude-handoff/README.md`, updating `.claude/HANDOFF.md` → `.handoff/HANDOFF.md`); uninstall. Use this skeleton and fill every section with real content (no placeholders):

```markdown
# handoff — cross-harness context handoff

Pause work in one AI coding harness, resume cleanly in the same or a different one.
Captures session state to a neutral `.handoff/HANDOFF.md`; a session-start hook auto-loads
it next time. Works in Claude Code, Codex CLI, and Gemini CLI.

## Supported harnesses

| Harness     | /handoff command | Auto-load | Notes |
|-------------|------------------|-----------|-------|
| Claude Code | ✅ plugin         | ✅ SessionStart | install via marketplace |
| Codex CLI   | ✅ prompt         | ✅ SessionStart | install.sh |
| Gemini CLI  | ✅ TOML command   | ✅ BeforeAgent  | install.sh |

## Install
### Claude Code (marketplace)
    /plugin marketplace add <repo-url-or-path>
    /plugin install handoff@claude-toolkit
### Codex + Gemini (script)
    ./install.sh            # detects ~/.codex and ~/.gemini, wires both
    ./install.sh --pointer  # also add a memory-file reminder
### Manual (any harness)
[exact per-harness steps: where to put the prompt/command, the hook JSON/TOML with the
absolute path to core/handoff-loader.sh and the correct harness arg]

## Usage
    /handoff            # write/update .handoff/HANDOFF.md
    /handoff status     # preview
    /handoff list       # active + archives
    /handoff clear      # archive (default) or delete
    /handoff help

## Auto-snapshot (opt-in safety net)
[explain mechanical snapshot; show the exact PreCompact/Stop (Claude/Codex) and AfterAgent
(Gemini) hook block calling core/handoff-snapshot.sh; note it is pointer-only on load and
never clobbers a manual handoff]

## Should I commit .handoff/HANDOFF.md?
[port the commit-vs-ignore trade-offs + the cross-machine symlink recipe + dedicated-branch
option from the original README, with .handoff/ paths and .handoff/archive-* in .gitignore]

## Uninstall
[Claude: /plugin uninstall handoff. Codex/Gemini: remove the installed prompt/command +
hook entries. Existing .handoff/ files are left untouched.]

## License
MIT
```

- [ ] **Step 2: Run the full test suite**

Run: `bash tests/run.sh`
Expected: every `*_test.sh` reports `N passed, 0 failed`; overall exit 0.

- [ ] **Step 3: Smoke-test a real loader round-trip**

```bash
T=$(mktemp -d); mkdir -p "$T/.handoff"
printf -- '---\nupdated: now\nsummary: smoke\nresume: do X\n---\n\n# Handoff\n\n## Next\n1. do X\n' > "$T/.handoff/HANDOFF.md"
printf '{"cwd":"%s"}' "$T" | bash core/handoff-loader.sh claude | head -5
GEMINI_CWD="$T" bash core/handoff-loader.sh gemini </dev/null | jq -r '.hookSpecificOutput.additionalContext' | head -3
```
Expected: claude prints the full-inject header + body; gemini prints the same body extracted from valid JSON.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: cross-harness README (install, autosave, commit guidance, uninstall)"
```

---

## Self-Review (completed during planning)

**Spec coverage:** §Storage→Tasks 2-7 use `.handoff/`. §Single loader→Tasks 2-5. §Shared body→Task 7. §Adapters→Tasks 8-10. §Memory pointer→Task 11 (`--pointer`). §install.sh+manual→Tasks 11-12. §Auto-snapshot (pointer-only, capped, no-clobber, precedence)→Tasks 5+6. §Test surface (synthetic stdin / $GEMINI_CWD / $PWD, full/pointer/stale/missing, AUTOSAVE precedence, archive isolation)→Tasks 2-6. §Copilot excluded→no task. §Gemini JSON output→Task 4. ✅ no gaps.

**Placeholder scan:** every code/JSON/TOML/bash block is complete and runnable; the only `{{...}}` tokens are deliberate installer placeholders, resolved + tested in Task 11. README skeleton (Task 12) marks bracketed sections the implementer must fill with real content — flagged explicitly, not silent TBDs.

**Type/name consistency:** loader arg values `claude|codex|gemini` consistent across Tasks 2,8,9,10,11. Functions `build_body`/`emit`/`no_handoff_body`/`autosave_body`/`resume_flow_instruction` defined before use. Frontmatter keys written by snapshot (`branch`/`dirty`/`commits`, Task 6) match those read by `autosave_body` (Task 5). Paths `.handoff/HANDOFF.md` + `.handoff/AUTOSAVE.md` + `.handoff/archive-*` consistent throughout. `{{HANDOFF_ROOT}}` placeholder written in Tasks 9-10, resolved in Task 11.
