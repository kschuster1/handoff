---
description: Manage .handoff/HANDOFF.md — write/update (default), clear, status, list, help
argument-hint: "[clear|status|list|help]"
---

# /handoff — Context handoff manager

Subcommand argument received: **$ARGUMENTS**

## Interactive questions (harness-neutral)

Whenever this command says "ask the user": if an interactive question tool
(e.g. AskUserQuestion) is available, you MUST call it — render the options as
selectable choices, each with a one-line description. Never substitute a flat
bracketed text prompt like `[Yes / No]` when the tool exists. Only fall back to
a plain numbered list (and wait for the reply) when no such tool is available.

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

Show the full draft, then ask the user via the interactive tool (header
`Confirm write`, question `Write this to .handoff/HANDOFF.md?`). Present these
selectable options, each with its one-line description:

- **Yes, write it** — Overwrite `.handoff/HANDOFF.md` with the draft above.
- **Clear instead** — *(include this option ONLY if the task looks shipped — PR open / work complete)* run `/handoff clear` (archive) rather than keep stale resume state.
- **Edit a section** — Revise part of the draft before writing.

(The tool auto-provides a free-text / "chat about this" escape — do not add a
manual Cancel option.)

Then act on the choice:
- Yes → Write file.
- Clear instead → run the CLEAR flow.
- Edit a section → ask which section, revise, re-confirm (loop back to this step).
- Free-text escape / cancel → discard, leave `HANDOFF.md` unchanged.

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
