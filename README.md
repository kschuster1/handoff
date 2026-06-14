# handoff — cross-harness context handoff

Pause work in one AI coding harness, resume cleanly in the same one **or a different one**.
`/handoff` captures session state to a neutral `.handoff/HANDOFF.md`; a session-start hook
auto-loads it next time. Write it in Claude Code, resume it in Codex or Gemini — the handoff
file is tool-agnostic.

Works in **Claude Code**, **Codex CLI**, and **Gemini CLI**.

## Why

The #1 failure mode of "where was I?" notes is drift: aspirational `[done]` items, paraphrased
errors, decisions recorded as settled when they're still open. `/handoff` verifies state against
`git status` / `git log` before writing, tags every item with evidence, and quotes errors
verbatim. The next session loads a handoff you can trust.

## Supported harnesses

All three deliver a stdin JSON payload (`.cwd`) to a `SessionStart` hook and accept injected
context, so one loader serves all of them; only the output format differs (Gemini requires a
JSON envelope).

| Harness     | `/handoff` command | Auto-load (`SessionStart` hook) | Install      | Verified                      |
|-------------|--------------------|---------------------------------|--------------|-------------------------------|
| Claude Code | ✅ plugin command   | ✅                              | marketplace  | runnable where you read this  |
| Codex CLI   | ✅ prompt           | ✅ `~/.codex/hooks.json`        | `install.sh` | wired to official docs¹       |
| Gemini CLI  | ✅ TOML command     | ✅ `~/.gemini/settings.json`    | `install.sh` | wired to official docs¹       |

¹ The Codex/Gemini wiring is built to each tool's **official** hook spec and exercised by 79
synthetic tests, but has not yet been run inside a live Codex/Gemini session in this repo. Do
the 30-second smoke test under [Verifying it works](#verifying-it-works) on first install.

Everything shares one loader (`core/handoff-loader.sh`) and one command body
(`core/handoff.md`). Adding a harness later is wiring, not a rewrite.

## How auto-load behaves

The loader is freshness-gated so it never floods a fresh context window:

- **< 24h and < 8KB** → full inject (handoff is in context immediately).
- **24h–7d, or ≥ 8KB** → pointer + summary (model reads the file on demand).
- **> 7d** → pointer + `⚠ STALE` warning (verify before trusting).
- `inject: full` / `inject: pointer` frontmatter overrides the auto-decision.

No handoff present → a single `∅ No handoff available` line, nothing else.

## Install

### Claude Code (marketplace)

```
/plugin marketplace add <repo-url-or-local-path>
/plugin install handoff@claude-toolkit
```

Enable in the `/plugin` menu. The `SessionStart` hook and `/handoff` command register
automatically.

### Codex + Gemini (script)

```
./install.sh            # detects ~/.codex and ~/.gemini, wires whichever exist
./install.sh --pointer  # also append a memory-file reminder (AGENTS.md / GEMINI.md)
./install.sh --harness gemini   # limit to one harness (repeatable)
```

`install.sh` copies `core/handoff.md` into the harness prompt/command dir and **merges** the
hook into the harness config (it backs up and preserves any hooks/settings you already have —
it never blind-overwrites). It bakes in the repo's absolute path, so re-run it after moving the
repo.

> **Codex:** lifecycle hooks may need enabling — set `features.hooks` in `~/.codex/config.toml`
> if your Codex version gates them. Run `/hooks` inside Codex to confirm the handoff hook loaded.

### Manual (any harness)

The pieces are: (1) the command body, (2) a session-start hook that runs the loader with the
right harness arg. Replace `/ABS/PATH` with this repo's absolute path.

**Codex** — `~/.codex/prompts/handoff.md` = a copy of `core/handoff.md`.
`~/.codex/hooks.json`:
```json
{ "SessionStart": [ { "hooks": [
  { "type": "command", "command": "bash \"/ABS/PATH/core/handoff-loader.sh\" codex", "timeout": 5 }
] } ] }
```

**Gemini** — `~/.gemini/commands/handoff.toml`:
```toml
description = "Manage .handoff/HANDOFF.md — write/update (default), clear, status, list, help"
prompt = """
@{/ABS/PATH/core/handoff.md}

Subcommand argument: {{args}}
"""
```
Gemini hooks live in `~/.gemini/settings.json` under a top-level `hooks` object (merge this in
— don't overwrite your other settings; note Gemini timeouts are **milliseconds**):
```json
{ "hooks": { "SessionStart": [
  { "type": "command", "command": "bash \"/ABS/PATH/core/handoff-loader.sh\" gemini", "timeout": 5000 }
] } }
```

**Claude Code (manual, without marketplace)** — add this repo dir as a plugin: the repo root
is the plugin root (`.claude-plugin/plugin.json`, `commands/handoff.md`, `hooks/hooks.json` are
already wired with `${CLAUDE_PLUGIN_ROOT}`).

## Verifying it works

The synthetic test suite proves the loader/installer logic, but only a live session proves the
harness actually fires the hook. 30-second smoke test per harness:

1. In a project, create `.handoff/HANDOFF.md` (run `/handoff`, or hand-write one with a
   `summary:`/`resume:` frontmatter).
2. Start a fresh session of the harness **in that directory**.
3. Confirm the first response begins with a `🤝 Handoff …` line. If it doesn't:
   - **Claude Code:** check the plugin is enabled in `/plugin`.
   - **Codex:** run `/hooks`; if the handoff hook isn't listed, enable `features.hooks` (above).
   - **Gemini:** confirm the `SessionStart` block landed in `~/.gemini/settings.json` and that
     `bash ~/.gemini/... </dev/null` style invocation isn't blocked.

A handoff written in one harness should produce the same `🤝` line when you open the project in
another — that round-trip is the whole point.

## Usage

```
/handoff            # write/update .handoff/HANDOFF.md (default)
/handoff status     # preview current handoff (read-only)
/handoff list       # active + archived handoffs
/handoff clear      # archive (default) or delete
/handoff help       # menu
```

Typical flow: work until you need to stop → `/handoff` (it verifies against git, drafts,
confirms, writes) → next session auto-loads it and offers to resume → `/handoff clear` when the
work is done so a stale handoff doesn't haunt the next session.

## Auto-snapshot (safety net for forgotten `/handoff`)

For the "I cleared / quit without running `/handoff`" case, `core/handoff-snapshot.sh` writes a
**mechanical** git snapshot to `.handoff/AUTOSAVE.md` — no model involved, so it's always
factually accurate. It is **size-capped** and **pointer-only on load** (the loader emits one
line, never injects the body), it **never clobbers** a manual `HANDOFF.md`, and it adds
`.handoff/AUTOSAVE.md` to the repo's `.gitignore` so the breadcrumb never shows up uninvited in
`git status`. It self-gates: nothing is written unless the tree is dirty or there are commits
ahead of upstream.

**It is a breadcrumb, not a handoff.** It captures git ground-truth (branch, dirty files,
recent commits, `diff --stat`) — not the decisions, blockers, or next-steps a written handoff
holds. For the good version, run `/handoff` *before* clearing. (At clear/exit time no model is
running — only a shell hook — so a narrative handoff is impossible to generate then.)

### Claude Code — built in (default-on)
The plugin ships these hooks in `hooks/hooks.json`, so the snapshot fires automatically:
- **`SessionEnd`** → covers `/clear`, quit, and logout.
- **`PreCompact`** → covers `/compact` and auto-compaction.

No setup needed. (`Stop` is deliberately not wired — it fires every turn; `SessionEnd` already
covers exit.)

### Codex / Gemini — `./install.sh --autosave` (experimental)
Their hook-event support is **unverified**, so this path is experimental and easy to undo (each
merge backs up to `<config>.bak`). It wires:
- **Codex** (`~/.codex/hooks.json`): `SessionEnd` + `PreCompact` → `core/handoff-snapshot.sh`.
- **Gemini** (`~/.gemini/settings.json`): `AfterAgent` → `core/handoff-snapshot.sh`.

When a snapshot exists and no manual handoff does, the next session shows:
`🤝 Auto-snapshot available — read .handoff/AUTOSAVE.md if resuming`.

## Should I commit `.handoff/HANDOFF.md`?

A project-level decision. The tool forces neither way.

**Commit it** for cross-machine resume or team handoff. Best for solo private repos, pair/team
workflows where the next person genuinely picks up your state, and repos with no
secrets-in-errors risk.

**Ignore it** if the repo is public/shared, if verbatim errors might capture credentials or
internal hostnames/paths (the handoff captures errors verbatim by design), or if you'd rather
not see handoff diffs in PRs.

Regardless of choice, always ignore the archives and snapshots:
```
.handoff/archive-*.md
.handoff/AUTOSAVE.md
```

### Cross-machine sync without committing (symlink recipe)

```bash
mkdir -p ~/Dropbox/handoffs/<repo-name>     # or iCloud / Drive / Syncthing path
mkdir -p .handoff
ln -s ~/Dropbox/handoffs/<repo-name>/HANDOFF.md .handoff/HANDOFF.md
echo ".handoff/HANDOFF.md"     >> .gitignore
echo ".handoff/archive-*.md"   >> .gitignore
echo ".handoff/AUTOSAVE.md"    >> .gitignore
```

On a second machine, clone and re-create the symlink — the handoff appears automatically. The
loader follows symlinks transparently.

### If you do commit it

- Always `.gitignore` the archives and `AUTOSAVE.md` (they accumulate fast, useless in history).
- Treat handoff edits as fixup commits — squash before merging feature branches.
- Consider `git-crypt` on `.handoff/HANDOFF.md` if errors-with-paths is a leak concern.

## Uninstall

- **Claude Code:** `/plugin uninstall handoff`.
- **Codex:** remove `~/.codex/prompts/handoff.md` and the `SessionStart` entry from
  `~/.codex/hooks.json`.
- **Gemini:** remove `~/.gemini/commands/handoff.toml` and the `SessionStart` entry from the
  `hooks` object in `~/.gemini/settings.json` (a `.bak` from install is alongside it).

Existing `.handoff/` files in your projects are left untouched — delete manually if desired.

## Development

Tests are dependency-light bash (require `jq`):

```
bash tests/run.sh
```

`core/handoff.md` is the single source of truth for the command body. Claude Code and Codex
loaders don't follow symlinks in their plugin/prompt caches, so `commands/handoff.md` and
`adapters/codex/prompts/handoff.md` are **copies**. `tests/cmd_sync_test.sh` fails if a copy
drifts — after editing `core/handoff.md`, re-copy it over both:

```
cp core/handoff.md commands/handoff.md
cp core/handoff.md adapters/codex/prompts/handoff.md
```

## License

MIT
