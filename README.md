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

| Harness     | `/handoff` command        | Auto-load              | Install        |
|-------------|---------------------------|------------------------|----------------|
| Claude Code | ✅ plugin command          | ✅ `SessionStart` hook | marketplace    |
| Codex CLI   | ✅ prompt                  | ✅ `SessionStart` hook | `install.sh`   |
| Gemini CLI  | ✅ TOML command            | ✅ `BeforeAgent` hook  | `install.sh`   |

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

`install.sh` copies `core/handoff.md` into the harness prompt/command dir and writes a
hook file with the repo's absolute path baked in. Re-run it after moving the repo.

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
`~/.gemini/hooks.json`:
```json
{ "BeforeAgent": [ { "hooks": [
  { "type": "command", "command": "bash \"/ABS/PATH/core/handoff-loader.sh\" gemini", "timeout": 5 }
] } ] }
```

**Claude Code (manual, without marketplace)** — add this repo dir as a plugin: the repo root
is the plugin root (`.claude-plugin/plugin.json`, `commands/handoff.md`, `hooks/hooks.json` are
already wired with `${CLAUDE_PLUGIN_ROOT}`).

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

## Auto-snapshot (opt-in safety net)

For the "I forgot to run `/handoff`" case, `core/handoff-snapshot.sh` writes a **mechanical**
git snapshot to `.handoff/AUTOSAVE.md` — no model involved, so it's always factually accurate.
It is **size-capped** and **pointer-only on load** (the loader emits one line, never injects the
body), and it **never clobbers** a manual `HANDOFF.md`. It self-gates: nothing is written unless
the tree is dirty or there are commits ahead of upstream.

Wire it to a pre-exit / pre-compact event (events differ per harness). Replace `/ABS/PATH`:

**Claude Code / Codex** — add to the harness `hooks.json` (alongside `SessionStart`):
```json
"PreCompact": [ { "hooks": [
  { "type": "command", "command": "bash \"/ABS/PATH/core/handoff-snapshot.sh\"", "timeout": 5 }
] } ],
"Stop": [ { "hooks": [
  { "type": "command", "command": "bash \"/ABS/PATH/core/handoff-snapshot.sh\"", "timeout": 5 }
] } ]
```

**Gemini** — add to `~/.gemini/hooks.json`:
```json
"AfterAgent": [ { "hooks": [
  { "type": "command", "command": "bash \"/ABS/PATH/core/handoff-snapshot.sh\"", "timeout": 5 }
] } ]
```

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
- **Gemini:** remove `~/.gemini/commands/handoff.toml` and the `BeforeAgent` entry from
  `~/.gemini/hooks.json`.

Existing `.handoff/` files in your projects are left untouched — delete manually if desired.

## Development

Tests are dependency-light bash (require `jq`):

```
bash tests/run.sh
```

## License

MIT
