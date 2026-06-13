# Cross-Harness Handoff — Design

**Date:** 2026-06-13
**Status:** Approved — **superseded in part during implementation** (see correction below)

> **CORRECTION (post-implementation):** the Gemini details in this doc came from a third-party
> source and were wrong. Per Gemini's *official* hook reference, Gemini fires `SessionStart`
> (not `BeforeAgent`, which is per-prompt), passes cwd via **stdin JSON `.cwd`** (not
> `$GEMINI_CWD`), and configures hooks in **`~/.gemini/settings.json`** under a `hooks` object
> (not a standalone `hooks.json`). The shipped code uses the corrected contract — all three
> harnesses now share `SessionStart` + stdin `.cwd`. The README reflects the as-built behaviour.
**Target harnesses:** Claude Code, Codex CLI, Gemini CLI (Copilot CLI explicitly out of scope)

## Problem

`claude-handoff` is a Claude Code plugin that captures session state to `.claude/HANDOFF.md`
and auto-injects it on the next session start, so work resumes cleanly. It is locked to one
harness: the storage path lives in Claude Code's private dir, the slash command uses Claude
Code's plugin/marketplace packaging, and the loader hook and command body reference Claude
Code-only mechanics (`${CLAUDE_PLUGIN_ROOT}`, `AskUserQuestion`).

Developers switch tools mid-project (Claude Code ⇄ Codex ⇄ Gemini). The handoff written in
one tool should resume in another. Convert the plugin into a cross-harness tool.

## Core principle: decompose by feature, not by harness

Two separable capabilities with very different portability:

1. **Portable write + neutral storage** — the must-have. A handoff written in any harness is
   readable by any other. Pure markdown/TOML plus a neutral file path. Works everywhere,
   hooks or not.
2. **Auto-load on session start** — the convenience layer. Tiered by each harness's hook
   capability. Where a session-start hook exists, the handoff injects automatically; where it
   doesn't, a memory-file pointer degrades it to instructed-load.

Make #1 rock-solid across all targets. Tier only #2.

## Harness capability matrix (verified against official docs, June 2026)

| Harness | Slash command | Session-start hook | cwd source | Hook output | Memory file |
|---|---|---|---|---|---|
| Claude Code | `commands/*.md`, `$ARGUMENTS` | `SessionStart` (hooks.json) | stdin JSON `.cwd` | plain stdout → context | CLAUDE.md |
| Codex CLI | `~/.codex/prompts/*.md`, `$ARGUMENTS` | `SessionStart` (hooks.json / config.toml) | stdin JSON `.cwd` | plain stdout → context (JSON shape also accepted) | AGENTS.md |
| Gemini CLI | `~/.gemini/commands/*.toml`, `{{args}}`, supports `@{file}` include | `BeforeAgent` hook | env `$GEMINI_CWD` | **requires** JSON `hookSpecificOutput.additionalContext` | GEMINI.md |

Sources: developers.openai.com/codex/hooks, developers.openai.com/codex/custom-prompts,
geminicli.com/docs/hooks/writing-hooks, google-gemini.github.io/gemini-cli custom-commands.

**Copilot CLI is out of scope** — prompt-file slash commands are unrecognized upstream
(github/copilot-cli#618) and its session-start hook is unconfirmed. The neutral storage path
keeps the door open to add it later with zero rework.

## Storage path

`.handoff/HANDOFF.md` (active) and `.handoff/archive-*.md` (archived). Harness-neutral hidden
dir — no tool's private directory owns the handoff. The loader ignores `archive-*` files.

This is the one breaking change from `claude-handoff` (`.claude/HANDOFF.md` → `.handoff/HANDOFF.md`).

## Components

### 1. `core/handoff-loader.sh` — single parameterized loader

One script, invoked as `handoff-loader.sh [claude|codex|gemini]` (arg set by each harness's
wiring, not auto-detected). The arg selects two things; everything else is identical:

- **cwd source:**
  - `claude` / `codex`: read stdin JSON, `cwd = .cwd` (jq), fallback `$PWD`.
  - `gemini`: `cwd = $GEMINI_CWD`, fallback `$PWD`.
- **output mode:**
  - `claude` / `codex`: emit the handoff block as plain stdout (current behaviour).
  - `gemini`: emit `{"hookSpecificOutput":{"hookEventName":"BeforeAgent","additionalContext":"<block>"}}`
    (JSON to stdout only; logs, if any, to stderr).

Shared body logic (unchanged from the original loader):
- No handoff file → emit the "no handoff" confirmation instruction.
- Handoff present → parse frontmatter (`summary`, `resume`, `inject`), compute age from mtime,
  estimate tokens (`chars/4`), choose mode:
  - `inject: full` / `inject: pointer` → honor override.
  - else `< 24h` AND `< 8192 chars` → **full** inject; otherwise **pointer**.
  - `> 7d` → append ⚠ STALE warning.
- Emit the resume-flow instruction (confirmation line + resume preview + resume question),
  with the interactive-question step phrased harness-neutrally (see §3).

`hookEventName` for gemini is `BeforeAgent`; if uniform JSON output is later wanted for
claude/codex it would be `SessionStart`. Plain stdout is retained for claude/codex because it
is simpler and fully supported.

### 2. `core/handoff.md` — shared command body

The full WRITE (default) / CLEAR / STATUS / LIST / HELP flow, carried over from
`claude-handoff/commands/handoff.md` with three edits:

- Storage path references `.claude/HANDOFF.md` → `.handoff/HANDOFF.md` throughout.
- `AskUserQuestion` references → harness-neutral phrasing: *"If an interactive question tool
  (e.g. AskUserQuestion) is available, use it; otherwise ask inline as a numbered list and
  wait for the user's choice."* Preserves Claude Code's native picker; works in Codex/Gemini.
- Frontmatter (`description`, `argument-hint`) and `$ARGUMENTS` are already compatible with
  Claude Code and Codex. Gemini consumes this body via `@{}` include (see §3).

### 3. Per-harness adapters (thin wiring only)

```
adapters/claude/
  .claude-plugin/plugin.json        # manifest (name, version, author, license, keywords)
  commands/handoff.md               # = core/handoff.md (symlinked or copied by installer)
  hooks/hooks.json                  # SessionStart → bash "${CLAUDE_PLUGIN_ROOT}/.../handoff-loader.sh" claude
adapters/codex/
  prompts/handoff.md                # = core/handoff.md
  hooks.json                        # SessionStart → handoff-loader.sh codex
adapters/gemini/
  commands/handoff.toml             # prompt = "@{<abs path>/core/handoff.md}\n\n{{args}}"
  hooks.json (or settings snippet)  # BeforeAgent → handoff-loader.sh gemini
```

Claude Code keeps its plugin/marketplace packaging (`.claude-plugin/plugin.json` +
toolkit-root `marketplace.json`). Codex and Gemini have no marketplace — the installer drops
files into `~/.codex` and `~/.gemini`.

### 4. Universal memory-file pointer (auto-load fallback)

For any harness where the hook is absent or disabled, the installer can append one line to the
harness memory file (CLAUDE.md / AGENTS.md / GEMINI.md):

> If `.handoff/HANDOFF.md` exists, read it at session start before responding.

Idempotent (guarded by a marker comment). This is the graceful-degradation layer; hooks are
preferred where available.

### 5. `install.sh` + manual docs

- Detects `~/.claude`, `~/.codex`, `~/.gemini`. For each present harness, wires the adapter
  (symlink core files where possible so `git pull` propagates updates; copy where symlinks
  aren't viable).
- Prompts before touching memory files.
- README documents the equivalent manual steps per harness for users who prefer not to run
  the script or are on an unsupported layout.

### 6. `core/handoff-snapshot.sh` — mechanical auto-snapshot (opt-in safety net)

Covers the "I forgot to run `/handoff`" gap without a model turn. A shell-only script wired to
a pre-exit / pre-compact event per harness (Claude Code `PreCompact` + `Stop`, Codex
`PreCompact` / `Stop`, Gemini `AfterAgent`). It dumps git ground-truth — no model involved, so
it is always factually accurate but has no Task/Decisions/Next narrative.

**Context-safety is the governing constraint** (it must not clobber the next window):

- **Size-capped at write time.** Output = header (branch, N commits ahead of upstream, N files
  dirty) + `git log --oneline -5` + `git diff --stat | head -20` + truncation marker. Target
  < 1KB on disk.
- **Pointer-only at load time, always.** Written to a distinct file `.handoff/AUTOSAVE.md`. The
  loader never full-injects it — it emits a single line
  (`⚠ auto-snapshot: <branch>, N files dirty, M commits — read .handoff/AUTOSAVE.md if resuming`).
  The model reads the file on demand only if it is resuming. Roughly one line of context cost.
- **Never clobbers a manual handoff.** Distinct filename; precedence handled in the loader.
- **Opt-in.** Off by default; enabled per harness by the installer (or manual wiring). Trigger
  is gated to a "significant run" — only writes when there is something to capture (dirty tree
  or commits ahead of upstream), so a no-op session leaves no snapshot.

**Loader precedence (added to §1):**
1. `.handoff/HANDOFF.md` exists → existing full/pointer/stale logic; AUTOSAVE ignored.
2. else `.handoff/AUTOSAVE.md` exists → pointer-only line, never full inject.
3. else → no-handoff confirmation line.

Not in scope here: a model-authored auto-handoff at end of run (Claude Code `Stop` hook with
`decision:block` re-prompting the model to run the full write flow). It is Claude-Code-specific,
intrusive, and needs significance + loop-guard gating. Deferred — see Out of scope.

### 7. `tests/loader_test.sh` — the verifiable surface

The loader is the only component testable without the harnesses installed. The test drives it
with synthetic inputs and asserts behaviour:

- **cwd resolution:** stdin `{"cwd":"<tmp>"}` (claude/codex), `$GEMINI_CWD=<tmp>` (gemini),
  bare `$PWD` (fallback) — each resolves to the right handoff path.
- **modes:** fixture handoffs produce full / pointer / stale / missing-file output correctly
  (manipulate mtime and file size to cross the 24h / 8KB / 7d thresholds).
- **output wrapping:** `gemini` output is valid JSON with `hookSpecificOutput.additionalContext`;
  `claude`/`codex` output is plain text.
- **archive isolation:** `archive-*.md` files are ignored.
- **AUTOSAVE precedence:** with both files present, `HANDOFF.md` wins; with only `AUTOSAVE.md`,
  output is a single pointer line (never full inject); snapshot script output stays < 1KB.

## Data flow

```
WRITE:  /handoff (any harness) → core/handoff.md flow → git-verified draft
        → confirm → write .handoff/HANDOFF.md
RESUME: session start (other harness) → hook runs handoff-loader.sh <harness>
        → reads .handoff/HANDOFF.md → injects (plain stdout | JSON additionalContext)
        → model emits confirmation + resume question
AUTO:   pre-compact / pre-exit event → handoff-snapshot.sh (shell only, no model)
        → if dirty tree or commits-ahead → writes size-capped .handoff/AUTOSAVE.md
        → next session: loader emits one pointer line (never full inject)
```

## What is preserved from `claude-handoff`

All accuracy guards stay (they are harness-independent prompt logic): git-as-ground-truth
pre-draft step; `[done]` requires commit/`file:line` evidence or demotes to `[wip]`;
`[locked]` decisions need committed backing; verbatim error capture; freshness gating; archive
default on clear; token budget (<600 target, 2000 hard cap → forces pointer mode).

## Out of scope (YAGNI)

- Copilot CLI integration.
- Model-authored auto-handoff at end of run (Claude Code `Stop` hook `decision:block`
  re-prompting the full write flow). Deferred: Claude-Code-only, intrusive, needs significance
  + loop-guard gating. The mechanical AUTOSAVE snapshot (§6) covers the "forgot to run
  `/handoff`" gap portably and without context bloat.
- Auto-detecting harness from inside the loader (the wiring passes it explicitly — simpler,
  deterministic).
- Cross-machine sync mechanics beyond the README recipes already documented.
- A build-time generator (only one shared body + one shared loader; direct symlink/copy suffices).

## Open risks

- **Gemini hook cwd:** docs confirm `$GEMINI_CWD` exists but are not 100% explicit it is set
  for `BeforeAgent`. Loader falls back to `$PWD`; verify on a real Gemini session during
  implementation. Low blast radius (fallback covers it).
- **Gemini `@{}` absolute path:** the TOML include needs an absolute path to `core/handoff.md`;
  the installer resolves and writes it. If the repo moves, re-run the installer.
