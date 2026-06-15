# Design: Handoff as a dual Claude + Codex plugin with a lean release branch

**Date:** 2026-06-15
**Status:** Approved (pending implementation plan)
**Supersedes:** the `install.sh`-clones-the-repo distribution model

## Problem

Today handoff installs on Codex by an agent cloning the whole repo and `install.sh`
baking the clone's **absolute path** into `~/.codex/hooks.json`. Consequences:

1. **The entire repo persists on disk forever** — the hooks point into the clone, so it
   can never be deleted. Only 3 files (`core/handoff-loader.sh`, `core/handoff-snapshot.sh`,
   `core/handoff.md`) are used at runtime; the other ~1.28 MB (`docs/`, `tests/`, `.git`,
   `README`, `install.sh`) is dead weight.
2. **Internal design docs leak.** `docs/superpowers/` (planning + spec docs) ships to disk,
   exposing the "superpowers" tooling on users' machines.
3. **No clean uninstall.** Removal is manual jq surgery on `hooks.json` plus `rm -rf` of the
   clone, and the exact clone path must be rediscovered.
4. **Fragile.** `install.sh` warns "re-run after moving the repo" because the path is baked in.

Verified empirically: the Claude marketplace already copies the **whole repo, per version,
kept 7 days** (`~/.claude/plugins/cache/claude-toolkit/handoff/{0.1.0…0.2.4}/`, each a full
copy including `docs/`, `tests/`, `superpowers/`).

## Root cause

We hand-rolled installation because we assumed Codex had no plugin system. It does. Codex
ships a first-class plugin marketplace that mirrors Claude's. We were doing by script what both
harnesses do natively.

## Verified platform facts (research, 2026-06-15)

| Capability | Claude Code | Codex CLI |
|---|---|---|
| Plugin manifest | `.claude-plugin/plugin.json` | `.codex-plugin/plugin.json` |
| Install command | `/plugin marketplace add <url>` → install | `codex plugin marketplace add owner/repo [--ref <branch>]` |
| Managed install dir | `~/.claude/plugins/` | `~/.codex/plugins/<name>` |
| Custom hooks file via manifest | ✅ `"hooks": "./hooks/claude.json"` | ✅ `"hooks": "./hooks/codex.json"` |
| Default `hooks/hooks.json` auto-loads | ✅ (would merge — must avoid) | ✅ same |
| Hook root variable | `${CLAUDE_PLUGIN_ROOT}` | `${PLUGIN_ROOT}` |
| `SessionEnd` event | ✅ exists | ❌ **does not exist** |
| Ignore / files-allowlist | ❌ none | ❌ none |
| Scope what ships | `git-subdir` source **or** branch ref | branch **ref only** (no subdir) |

Sources: developers.openai.com/codex/hooks, developers.openai.com/codex/plugins/build,
code.claude.com/docs plugins-reference + plugin-marketplaces.

Codex documented hook events: `SessionStart`, `SubagentStart`, `PreToolUse`,
`PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `UserPromptSubmit`,
`SubagentStop`, `Stop`. **No `SessionEnd`.**

## Design

### 1. Distribution: native dual plugin, installed from a lean `release` branch

One repository, two manifests, installed by each harness's own marketplace:

- **Claude:** `/plugin marketplace add kschuster1/handoff` → install
- **Codex:** `codex plugin marketplace add kschuster1/handoff --ref release` → install
- **Gemini:** unchanged — `install.sh` (Gemini has no plugin system)

Both marketplace sources point at the **`release` branch**, never `main`.

Because neither harness has an ignore mechanism and Codex can only scope by branch ref (not
subdir), the only reliable way to ship nothing dev-only is for the **installed branch to
contain nothing dev-only**. Hence the two-branch model:

- **`main`** — full development tree. Keeps `tests/`, `docs/` (including these specs),
  `install.sh`, everything. Where all work happens. Never installed directly.
- **`release`** — generated lean artifact. Contains exactly:
  - `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
  - `hooks/claude.json`, `hooks/codex.json`
  - `core/handoff-loader.sh`, `core/handoff-snapshot.sh`, `core/handoff.md`
  - `commands/handoff.md` (Claude command copy)
  - `adapters/gemini/` (for the manual/Gemini path) + `install.sh` (Gemini-only)
  - `README.md`, `LICENSE`
  - **No** `tests/`, **no** `docs/`, **no** planning artifacts.

`scripts/build-release.sh` regenerates `release` from `main` at each version bump (checkout
`release`, sync the allowlisted paths from `main`, commit, push). The allowlist lives in the
script so "what ships" is one auditable list.

**Why this satisfies every goal:** users get only runtime files; `docs/` stays browsable on
`main` (not lost, not shipped); `tests/` stay on `main` where they're developed (no rot, no
second repo); uninstall is native on both harnesses.

### 2. Per-harness hook files

Two hook files, each referenced from its own manifest. **No `hooks/hooks.json`** at the plugin
root (it would auto-load and merge over the custom file).

`hooks/claude.json` — uses `${CLAUDE_PLUGIN_ROOT}`:
- `SessionStart` → `core/handoff-loader.sh claude`
- `SessionEnd` + `PreCompact` → `core/handoff-snapshot.sh` (Claude has SessionEnd)

`hooks/codex.json` — uses `${PLUGIN_ROOT}`:
- `SessionStart` → `core/handoff-loader.sh codex`
- `PreCompact` (+ `PostCompact` if needed) → `core/handoff-snapshot.sh` — **no SessionEnd**

`.claude-plugin/plugin.json` adds `"hooks": "./hooks/claude.json"`.
`.codex-plugin/plugin.json` declares `"hooks": "./hooks/codex.json"` plus name/version/description.

The loader and snapshot scripts already accept the cwd from stdin `.cwd` and a harness arg;
they need no path baking — the harness supplies `${…PLUGIN_ROOT}` at runtime.

### 3. Autosave event correctness

`SessionEnd` is not a Codex event, so the current `adapters/codex/hooks-autosave.json`
(`SessionEnd`+`PreCompact`) half-wires nothing. Fix:

- Codex snapshot fires on `PreCompact` (covers the compact case) and `PostCompact`. Evaluate
  whether `Stop` is needed for a true session-end equivalent (likely too frequent — decide
  during implementation by reading the event semantics).
- Add the **event name** to the `HANDOFF_DEBUG` breadcrumb (currently logs `arg=none` for
  every fire, so we can't tell which event fired). Then re-verify live on Codex.
- Soften the memory note: the prior "Codex autosave VERIFIED — 2 fires (PreCompact+SessionEnd)"
  is unproven; we know snapshots fired twice but not from which events.

### 4. `install.sh` demoted to Gemini-only

`install.sh` keeps the Gemini wiring (`~/.gemini/`) and the manual fallback, and drops the
Codex path entirely (Codex now installs natively). The `{{HANDOFF_ROOT}}` render is only needed
for Gemini, whose settings still reference an absolute script path.

### 5. Tests

- Add: `.codex-plugin/plugin.json` schema validation; both manifests reference their custom
  hooks file; assert **no** `hooks/hooks.json` exists; `build-release.sh` allowlist matches the
  documented release contents.
- Retire: the codex `install.sh` adapter tests (codex no longer uses `install.sh`).
- Keep: loader, snapshot, command-sync, Gemini adapter, Claude manifest tests.

### 6. README

Rewrite the install section: Claude marketplace + Codex marketplace as parallel first-class
paths; Gemini via `install.sh`. Update the capability table. Document native uninstall on both.
Document the `release` branch + `build-release.sh` for maintainers.

### 7. Per-project behaviour: gitignore + one-time legacy migration

The plugin installs once globally (user-level `~/.codex/plugins/`, `~/.claude/plugins/`) and its
hooks fire in **every** project. The `.handoff/` data is per-project. Two per-project behaviours:

**7a. Ignore the whole `.handoff/` directory.** Wherever handoff writes into a project, ensure
the project `.gitignore` contains a `.handoff/` line (idempotent — added only if absent). This
supersedes the current AUTOSAVE-only ignore. Three entry points must guarantee it:
- `core/handoff-snapshot.sh` — change its existing `.handoff/AUTOSAVE.md` gitignore line to `.handoff/`.
- `core/handoff-loader.sh` — the migration path (7b) adds it.
- `core/handoff.md` WRITE flow — add a step that ensures `.handoff/` is ignored before writing.

**7b. Silent, one-time, reversible legacy migration (in the loader).** On `SessionStart`,
`core/handoff-loader.sh` migrates a legacy handoff into the new location. Chosen explicitly as
*silent* (no prompt), so it is constrained to be safe:

- **Trigger guard:** runs only if `./.handoff/HANDOFF.md` does **not** exist AND a legacy file
  does — `./.ai/HANDOFF.md` or `./.claude/HANDOFF.md` (first match wins). Once `.handoff/HANDOFF.md`
  exists, it can never fire again → strictly one-time.
- **Non-destructive:** `cp` legacy → `./.handoff/HANDOFF.md`, then `mv` legacy → `<legacy>.bak`
  (rename, never delete — fully reversible).
- **Gitignore:** ensure `.handoff/` in the project `.gitignore` (7a helper).
- **Strip stale memory refs:** in `./CLAUDE.md` and `./AGENTS.md`, back up to `<file>.bak` then
  remove lines referencing a legacy handoff path (`.ai/HANDOFF.md`, `.claude/HANDOFF.md`) or the
  `<!-- handoff-pointer -->` marker. The new model auto-loads via the SessionStart hook, so no
  memory-file pointer is needed — stale lines are removed, not rewritten.
- **Crash-proof:** every step guarded; the function always returns 0. A migration failure must
  never block session start or the normal injection that follows. Honour the 5s hook timeout —
  the work is a few file ops, well within budget.

The migrated `.handoff/HANDOFF.md` then flows through the normal loader injection unchanged.

## Out of scope

- Publishing to the public Codex Plugin Marketplace review queue (the `marketplace add owner/repo`
  path installs straight from the repo; public listing is a later, optional step).
- Gemini plugin-ification (Gemini has no plugin system; stays on `install.sh`).
- Live Gemini autosave verification (no Gemini access — unchanged).

## Migration / rollout

1. Build the `release` branch and verify both harnesses install from it cleanly on a scratch
   machine (or by inspecting the managed install dir).
2. Update the marketplace source refs to `release`.
3. Bump version; cut the first release-branch artifact.
4. Old clones on users' machines: documented manual cleanup (already written this session).

## Open items to resolve during implementation (not user decisions)

- Exact Codex snapshot event set (`PreCompact` only vs. `+PostCompact`/`Stop`) — decided by
  reading event semantics + the re-verify.
- Whether Claude's marketplace `source` should also use the `release` ref or stay on the
  default branch pointed at a subdir — prefer `release` ref for symmetry with Codex.
