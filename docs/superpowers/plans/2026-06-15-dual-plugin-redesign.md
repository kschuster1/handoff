# Dual Claude + Codex Plugin Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make handoff install as a native plugin on both Claude Code and Codex (each via its own marketplace, both served from a lean `release` branch), so nothing dev-only (docs/tests) ever lands on a user's machine.

**Architecture:** One repo, two plugin manifests (`.claude-plugin/`, `.codex-plugin/`), two per-harness hook files (`hooks/claude.json`, `hooks/codex.json` — no default `hooks/hooks.json`). `main` keeps the full dev tree; a generated `release` branch holds only runtime files. Both marketplaces install from the `release` ref. `install.sh` is demoted to Gemini-only.

**Tech Stack:** Bash, jq, JSON config. Tests are `tests/*_test.sh` shell-assertion scripts (`tests/lib.sh` provides `assert_*`/`finish`; `tests/run.sh` runs all). No application runtime.

**Hard constraint:** Codex is not installed on the dev machine, so no task can *live-install* on Codex. Codex coverage is JSON-structure tests plus a manual smoke-test checklist (Task 10). Claude install *can* be inspected on the dev machine.

---

## File Structure

**Created:**
- `.codex-plugin/plugin.json` — Codex plugin manifest (name/version/description, `hooks` → `./hooks/codex.json`).
- `.agents/plugins/marketplace.json` — Codex marketplace manifest (single-plugin entry, `source:local path:./`).
- `hooks/codex.json` — Codex hooks (`${PLUGIN_ROOT}`, SessionStart loader + PreCompact snapshot; **no SessionEnd**).
- `hooks/claude.json` — Claude hooks (renamed from `hooks/hooks.json`; `${CLAUDE_PLUGIN_ROOT}`; SessionStart + SessionEnd + PreCompact).
- `scripts/build-release.sh` — builds the lean `release` branch from an explicit allowlist.
- `tests/codex_plugin_test.sh`, `tests/hook_files_test.sh`, `tests/marketplace_test.sh`, `tests/build_release_test.sh` — new test files.

**Modified:**
- `.claude-plugin/plugin.json` — add `"hooks": "./hooks/claude.json"`.
- `.claude-plugin/marketplace.json` — plugin `source` → github repo `ref: release`.
- `core/handoff-snapshot.sh` — breadcrumb logs the firing event name via `HANDOFF_EVENT`.
- `install.sh` — remove the Codex block; Gemini + manual only.
- `README.md` — rewrite install/uninstall + capability table.
- `tests/cmd_sync_test.sh` — unchanged logic, but verify it still references real files.

**Deleted:**
- `hooks/hooks.json` — replaced by `hooks/claude.json` (a default `hooks/hooks.json` would auto-load and double-wire).
- `adapters/codex/hooks.json`, `adapters/codex/hooks-autosave.json`, `adapters/codex/prompts/handoff.md` — Codex no longer installs via `install.sh`.
- `tests/adapter_codex_test.sh` — obsolete (Codex install path removed).

---

### Task 1: Per-harness hook files (no default `hooks.json`)

**Files:**
- Create: `hooks/claude.json` (content moved from `hooks/hooks.json`)
- Create: `hooks/codex.json`
- Delete: `hooks/hooks.json`
- Modify: `.claude-plugin/plugin.json` (add `hooks` field)
- Test: `tests/hook_files_test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/hook_files_test.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

# A default hooks/hooks.json must NOT exist (it would auto-load and double-wire).
assert_eq "$([ -f "$ROOT/hooks/hooks.json" ] && echo present || echo absent)" "absent" "no default hooks/hooks.json"

# Claude hook file: valid JSON, uses CLAUDE_PLUGIN_ROOT, has SessionStart+SessionEnd+PreCompact.
cj=$(cat "$ROOT/hooks/claude.json")
echo "$cj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "claude.json valid JSON"
assert_contains "$cj" "\${CLAUDE_PLUGIN_ROOT}" "claude.json uses CLAUDE_PLUGIN_ROOT"
assert_contains "$cj" "handoff-loader.sh" "claude.json wires loader"
assert_json_field "$cj" '.hooks.SessionStart[0].hooks[0].type' "command" "claude SessionStart present"
assert_json_field "$cj" '.hooks.SessionEnd[0].hooks[0].type' "command" "claude SessionEnd present"
assert_json_field "$cj" '.hooks.PreCompact[0].hooks[0].type' "command" "claude PreCompact present"

# Codex hook file: valid JSON, uses PLUGIN_ROOT, SessionStart+PreCompact, and NO SessionEnd (not a Codex event).
xj=$(cat "$ROOT/hooks/codex.json")
echo "$xj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "codex.json valid JSON"
assert_contains "$xj" "\${PLUGIN_ROOT}" "codex.json uses PLUGIN_ROOT"
assert_not_contains "$xj" "CLAUDE_PLUGIN_ROOT" "codex.json does not use CLAUDE_PLUGIN_ROOT"
assert_json_field "$xj" '.hooks.SessionStart[0].hooks[0].type' "command" "codex SessionStart present"
assert_json_field "$xj" '.hooks.PreCompact[0].hooks[0].type' "command" "codex PreCompact present"
assert_eq "$(echo "$xj" | jq -r '.hooks | has("SessionEnd")')" "false" "codex.json has NO SessionEnd (not a Codex event)"

# Claude manifest points at the custom hooks file.
pj=$(cat "$ROOT/.claude-plugin/plugin.json")
assert_json_field "$pj" '.hooks' "./hooks/claude.json" "claude manifest references ./hooks/claude.json"
finish
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `bash tests/hook_files_test.sh`
Expected: FAILs (hooks/hooks.json still present, claude.json/codex.json absent, manifest has no `.hooks`).

- [ ] **Step 3: Create `hooks/claude.json`**

Copy the existing Claude config verbatim into the new name:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/core/handoff-loader.sh\" claude", "timeout": 5 } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/core/handoff-snapshot.sh\"", "timeout": 5 } ] }
    ],
    "PreCompact": [
      { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/core/handoff-snapshot.sh\"", "timeout": 5 } ] }
    ]
  }
}
```

- [ ] **Step 4: Create `hooks/codex.json`**

Note `${PLUGIN_ROOT}` (Codex's var), no `SessionEnd`, and `HANDOFF_EVENT` set per snapshot entry (used by Task 5's breadcrumb):

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash \"${PLUGIN_ROOT}/core/handoff-loader.sh\" codex", "timeout": 5 } ] }
    ],
    "PreCompact": [
      { "hooks": [ { "type": "command", "command": "HANDOFF_EVENT=PreCompact bash \"${PLUGIN_ROOT}/core/handoff-snapshot.sh\"", "timeout": 5 } ] }
    ]
  }
}
```

- [ ] **Step 5: Delete the default hooks file**

Run: `git rm hooks/hooks.json`

- [ ] **Step 6: Add the `hooks` field to the Claude manifest**

In `.claude-plugin/plugin.json`, add `"hooks": "./hooks/claude.json",` after the `"license"` line:

```json
  "license": "MIT",
  "hooks": "./hooks/claude.json",
  "keywords": ["handoff", "context", "session", "resume", "codex", "gemini", "cross-harness"]
```

- [ ] **Step 7: Run the test, verify it passes**

Run: `bash tests/hook_files_test.sh`
Expected: all `ok:`, `0 failed`.

- [ ] **Step 8: Commit**

```bash
git add hooks/claude.json hooks/codex.json .claude-plugin/plugin.json tests/hook_files_test.sh
git rm hooks/hooks.json
git commit -m "feat(hooks): split per-harness hook files, drop default hooks.json"
```

---

### Task 2: Codex plugin manifest

**Files:**
- Create: `.codex-plugin/plugin.json`
- Test: `tests/codex_plugin_test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/codex_plugin_test.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

pj=$(cat "$ROOT/.codex-plugin/plugin.json")
echo "$pj" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "codex plugin.json valid JSON"
assert_json_field "$pj" '.name' "handoff" "codex manifest name = handoff (matches claude)"
assert_json_field "$pj" '.hooks' "./hooks/codex.json" "codex manifest references ./hooks/codex.json"
assert_eq "$(echo "$pj" | jq -r 'has("version")')" "true" "codex manifest has version"
assert_eq "$(echo "$pj" | jq -r 'has("description")')" "true" "codex manifest has description"

# Versions must stay in lockstep with the Claude manifest.
cv=$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")
xv=$(echo "$pj" | jq -r '.version')
assert_eq "$xv" "$cv" "codex manifest version matches claude manifest version"
finish
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `bash tests/codex_plugin_test.sh`
Expected: FAIL (`.codex-plugin/plugin.json` does not exist).

- [ ] **Step 3: Create `.codex-plugin/plugin.json`**

Keep `version` identical to `.claude-plugin/plugin.json` (currently `0.2.4`):

```json
{
  "name": "handoff",
  "version": "0.2.4",
  "description": "Cross-harness per-project context handoff: write .handoff/HANDOFF.md when pausing, auto-load on session start so the next session (in any supported harness) resumes cleanly.",
  "hooks": "./hooks/codex.json"
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `bash tests/codex_plugin_test.sh`
Expected: all `ok:`, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add .codex-plugin/plugin.json tests/codex_plugin_test.sh
git commit -m "feat(codex): add .codex-plugin/plugin.json manifest"
```

---

### Task 3: Codex marketplace manifest

**Files:**
- Create: `.agents/plugins/marketplace.json`
- Test: add to `tests/marketplace_test.sh` (created here)

Codex reads `.agents/plugins/marketplace.json` from the `--ref`'d branch and installs the plugin at the `source.path` directory (which must contain `.codex-plugin/plugin.json`). Our plugin manifest is at repo root, so `path` is `./`.

- [ ] **Step 1: Write the failing test**

Create `tests/marketplace_test.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

# --- Codex marketplace manifest ---
cm=$(cat "$ROOT/.agents/plugins/marketplace.json")
echo "$cm" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "codex marketplace.json valid JSON"
assert_json_field "$cm" '.plugins[0].name' "handoff" "codex marketplace lists handoff"
assert_json_field "$cm" '.plugins[0].source.source' "local" "codex marketplace source type local"
assert_json_field "$cm" '.plugins[0].source.path' "./" "codex marketplace path points at repo root"

# --- Claude marketplace manifest points plugin at the release ref ---
am=$(cat "$ROOT/.claude-plugin/marketplace.json")
echo "$am" | jq . >/dev/null 2>&1; assert_eq "$?" "0" "claude marketplace.json valid JSON"
assert_json_field "$am" '.plugins[0].source.source' "github" "claude plugin source type github"
assert_json_field "$am" '.plugins[0].source.repo' "kschuster1/handoff" "claude plugin source repo"
assert_json_field "$am" '.plugins[0].source.ref' "release" "claude plugin source pinned to release branch"
finish
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `bash tests/marketplace_test.sh`
Expected: FAIL (`.agents/plugins/marketplace.json` absent; claude marketplace source still `"./"`).

- [ ] **Step 3: Create `.agents/plugins/marketplace.json`**

```json
{
  "name": "handoff",
  "plugins": [
    {
      "name": "handoff",
      "source": { "source": "local", "path": "./" },
      "category": "Productivity",
      "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" }
    }
  ]
}
```

- [ ] **Step 4: Run the test, verify it passes (Codex half)**

Run: `bash tests/marketplace_test.sh`
Expected: Codex assertions pass; Claude assertions still FAIL (fixed in Task 4).

- [ ] **Step 5: Commit**

```bash
git add .agents/plugins/marketplace.json tests/marketplace_test.sh
git commit -m "feat(codex): add .agents/plugins/marketplace.json"
```

---

### Task 4: Point Claude marketplace at the `release` ref

**Files:**
- Modify: `.claude-plugin/marketplace.json`
- Test: `tests/marketplace_test.sh` (Claude half, already written in Task 3)

- [ ] **Step 1: Confirm the test still fails on the Claude half**

Run: `bash tests/marketplace_test.sh`
Expected: `claude plugin source pinned to release branch` FAILs.

- [ ] **Step 2: Update `.claude-plugin/marketplace.json`**

Replace the plugin entry's `"source": "./"` with the github+ref object:

```json
{
  "name": "claude-toolkit",
  "owner": {
    "name": "Keith Schuster",
    "email": "keithschuster@gmail.com"
  },
  "plugins": [
    {
      "name": "handoff",
      "source": { "source": "github", "repo": "kschuster1/handoff", "ref": "release" },
      "description": "Cross-harness context handoff (Claude Code, Codex, Gemini)."
    }
  ]
}
```

- [ ] **Step 3: Run the test, verify it passes**

Run: `bash tests/marketplace_test.sh`
Expected: all `ok:`, `0 failed`.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/marketplace.json
git commit -m "feat(claude): install plugin from release branch ref"
```

---

### Task 5: Snapshot breadcrumb logs the firing event

**Files:**
- Modify: `core/handoff-snapshot.sh` (breadcrumb line)
- Test: `tests/snapshot_test.sh` (add one assertion)

The current breadcrumb logs `arg=none` for every fire, so we can't tell which event fired (this is why the earlier "Codex VERIFIED" claim was unprovable). Make the breadcrumb read an optional `HANDOFF_EVENT` env var (set per hook entry in `hooks/codex.json` and, optionally, `hooks/claude.json`).

- [ ] **Step 1: Read the current breadcrumb**

Run: `sed -n '1,16p' core/handoff-snapshot.sh`
Confirm the breadcrumb line matches the string in Step 3's `old` block before editing.

- [ ] **Step 2: Write the failing test**

Append to `tests/snapshot_test.sh` (before its `finish` call) — first read it to find the line:

```bash
# breadcrumb records the firing event when HANDOFF_EVENT is set
log="${TMPDIR:-/tmp}/handoff-snapshot-evttest.log"
rm -f "$log"
( cd "$ROOT" && HANDOFF_DEBUG=1 HANDOFF_EVENT=PreCompact TMPDIR="$(dirname "$log")/" \
  bash core/handoff-snapshot.sh </dev/null >/dev/null 2>&1 ) || true
# The breadcrumb file name is fixed inside the script; just assert event text landed in the dir's log.
assert_contains "$(cat "${TMPDIR:-/tmp}/handoff-snapshot.log" 2>/dev/null)" "event=PreCompact" "breadcrumb logs HANDOFF_EVENT name"
```

(Adjust the temp wiring to match how `snapshot_test.sh` already invokes the script — read the file first and mirror its existing `HANDOFF_DEBUG`/stdin pattern.)

- [ ] **Step 3: Run the test, verify it fails**

Run: `bash tests/snapshot_test.sh`
Expected: `breadcrumb logs HANDOFF_EVENT name` FAILs (breadcrumb prints `arg=`/`tty=` only).

- [ ] **Step 4: Update the breadcrumb in `core/handoff-snapshot.sh`**

Replace the existing breadcrumb line:

```bash
[ -n "$HANDOFF_DEBUG" ] && printf '%s entered (arg=%s tty=%s)\n' \
  "$(date -u +%FT%TZ)" "${1:-none}" "$([ -t 0 ] && echo yes || echo no)" \
  >> "${TMPDIR:-/tmp}/handoff-snapshot.log" 2>/dev/null || true
```

with one that includes the event:

```bash
[ -n "$HANDOFF_DEBUG" ] && printf '%s entered (event=%s arg=%s tty=%s)\n' \
  "$(date -u +%FT%TZ)" "${HANDOFF_EVENT:-none}" "${1:-none}" "$([ -t 0 ] && echo yes || echo no)" \
  >> "${TMPDIR:-/tmp}/handoff-snapshot.log" 2>/dev/null || true
```

- [ ] **Step 5: Run the test, verify it passes**

Run: `bash tests/snapshot_test.sh`
Expected: all `ok:`, `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add core/handoff-snapshot.sh tests/snapshot_test.sh
git commit -m "feat(snapshot): breadcrumb records firing event via HANDOFF_EVENT"
```

---

### Task 6: Demote `install.sh` to Gemini-only; remove Codex `install.sh` path

**Files:**
- Modify: `install.sh` (remove the Codex detection block and the Codex autosave block)
- Delete: `adapters/codex/hooks.json`, `adapters/codex/hooks-autosave.json`, `adapters/codex/prompts/handoff.md`
- Delete: `tests/adapter_codex_test.sh`
- Test: `tests/install_test.sh` (adjust — confirm it no longer asserts Codex wiring)

- [ ] **Step 1: Read the current install + test to find Codex references**

Run: `grep -n -i codex install.sh tests/install_test.sh`
Note every line to remove.

- [ ] **Step 2: Remove the Codex block from `install.sh`**

Delete the entire `# ── Codex ──` block (the `if want codex && [ -d "$HOME_DIR/.codex" ]; then … fi`) and the Codex branch inside the autosave section (`if want codex && [ -d "$HOME_DIR/.codex" ]; then merge_hooks … fi`). Leave Gemini, Claude-guidance, pointer, and `.bak` logic intact. Update the Codex line in the pointer loop only if it targets `~/.codex/AGENTS.md` — keep it (the pointer is still valid for Codex users who want a memory note), but the hook/prompt wiring must be gone.

- [ ] **Step 3: Update `install.sh` header comment**

Change the flags/summary comment so it states Codex now installs via its native plugin marketplace and `install.sh` handles Gemini + manual only.

- [ ] **Step 4: Delete obsolete Codex adapter files and test**

```bash
git rm adapters/codex/hooks.json adapters/codex/hooks-autosave.json adapters/codex/prompts/handoff.md
git rm tests/adapter_codex_test.sh
rmdir adapters/codex/prompts adapters/codex 2>/dev/null || true
```

- [ ] **Step 5: Fix `tests/cmd_sync_test.sh`**

It currently checks `adapters/codex/prompts/handoff.md` matches `core/handoff.md`. Remove those two assertions (the Codex prompt copy no longer exists); keep the `commands/handoff.md` checks.

- [ ] **Step 6: Run the suite, verify green**

Run: `bash tests/run.sh`
Expected: no failures; no test references the deleted Codex adapter files.

- [ ] **Step 7: Commit**

```bash
git add -A install.sh tests/cmd_sync_test.sh
git commit -m "refactor(install): demote install.sh to Gemini-only; remove Codex script path"
```

---

### Task 7: `scripts/build-release.sh` (lean release branch)

**Files:**
- Create: `scripts/build-release.sh`
- Test: `tests/build_release_test.sh`

The script stages exactly the allowlisted runtime files into a directory and verifies nothing dev-only leaked. A `HANDOFF_RELEASE_STAGE=<dir>` mode stages without touching git (used by the test). Without it, the script stages into a `release` git worktree, commits, and prints push instructions (it does **not** auto-push — publishing is outward-facing).

- [ ] **Step 1: Write the failing test**

Create `tests/build_release_test.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

stage=$(mktemp -d)
( cd "$ROOT" && HANDOFF_RELEASE_STAGE="$stage" bash scripts/build-release.sh ) >/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "build-release stage mode exits 0"

# Required runtime files present
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json \
         .codex-plugin/plugin.json .agents/plugins/marketplace.json \
         hooks/claude.json hooks/codex.json \
         core/handoff-loader.sh core/handoff-snapshot.sh core/handoff.md \
         commands/handoff.md README.md LICENSE; do
  assert_eq "$([ -f "$stage/$f" ] && echo y || echo n)" "y" "release includes $f"
done

# Dev-only files must NOT ship
assert_eq "$([ -d "$stage/docs" ] && echo y || echo n)" "n" "release excludes docs/"
assert_eq "$([ -d "$stage/tests" ] && echo y || echo n)" "n" "release excludes tests/"
assert_eq "$([ -f "$stage/hooks/hooks.json" ] && echo y || echo n)" "n" "release has no default hooks.json"
assert_eq "$([ -d "$stage/.git" ] && echo y || echo n)" "n" "release excludes .git"
rm -rf "$stage"
finish
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `bash tests/build_release_test.sh`
Expected: FAIL (`scripts/build-release.sh` does not exist).

- [ ] **Step 3: Create `scripts/build-release.sh`**

```bash
#!/usr/bin/env bash
# Build the lean `release` branch from an explicit allowlist.
# Stage-only mode (for tests/CI): HANDOFF_RELEASE_STAGE=<dir> bash scripts/build-release.sh
# Publish mode (default): stages into a `release` git worktree, commits, prints push steps.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

ALLOW=(
  .claude-plugin/plugin.json
  .claude-plugin/marketplace.json
  .codex-plugin/plugin.json
  .agents/plugins/marketplace.json
  hooks/claude.json
  hooks/codex.json
  core/handoff-loader.sh
  core/handoff-snapshot.sh
  core/handoff.md
  commands/handoff.md
  adapters/gemini
  install.sh
  README.md
  LICENSE
)

stage_into() { # dest_dir
  local dest="$1" item
  for item in "${ALLOW[@]}"; do
    if [ -e "$ROOT/$item" ]; then
      mkdir -p "$dest/$(dirname "$item")"
      cp -R "$ROOT/$item" "$dest/$(dirname "$item")/"
    fi
  done
  # safety: refuse to ship dev-only trees
  if [ -d "$dest/docs" ] || [ -d "$dest/tests" ]; then
    echo "ERROR: dev-only files leaked into release stage" >&2
    return 1
  fi
}

if [ -n "${HANDOFF_RELEASE_STAGE:-}" ]; then
  stage_into "$HANDOFF_RELEASE_STAGE"
  echo "Staged release into $HANDOFF_RELEASE_STAGE"
  exit 0
fi

# Publish mode
WT="$(mktemp -d)"
git worktree add --force -B release "$WT" >/dev/null
# wipe tracked content in the worktree, then restage from allowlist
( cd "$WT" && git rm -rqf . >/dev/null 2>&1 || true )
stage_into "$WT"
( cd "$WT" && git add -A && git commit -q -m "build: release $(jq -r .version "$ROOT/.claude-plugin/plugin.json")" || echo "no changes" )
echo "Release built in worktree: $WT"
echo "Review, then publish:  git -C \"$WT\" push -u origin release"
echo "Cleanup when done:      git worktree remove \"$WT\""
```

- [ ] **Step 4: Make it executable and run the test**

```bash
chmod +x scripts/build-release.sh
bash tests/build_release_test.sh
```
Expected: all `ok:`, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/build-release.sh tests/build_release_test.sh
git commit -m "feat(release): build-release.sh stages a lean release branch from allowlist"
```

---

### Task 8: Full suite green + version lockstep

**Files:**
- Test: all `tests/*_test.sh`

- [ ] **Step 1: Run the whole suite**

Run: `bash tests/run.sh`
Expected: every file reports `0 failed`; total reflects removed Codex-adapter tests and the four new files.

- [ ] **Step 2: Fix any drift**

If `cmd_sync_test.sh` or `install_test.sh` still reference deleted Codex files, remove those assertions. Re-run until green.

- [ ] **Step 3: Commit (only if fixes were needed)**

```bash
git add -A tests/
git commit -m "test: reconcile suite with dual-plugin restructure"
```

---

### Task 9: README rewrite

**Files:**
- Modify: `README.md` (capability table, Install, Uninstall, maintainer release note)

- [ ] **Step 1: Update the capability table**

Set the Install column: Claude = `marketplace`, Codex = `marketplace`, Gemini = `install.sh`. Drop the "wired to official docs" footnote for Codex install (it's native now) but keep the live-verification caveat for autosave events.

- [ ] **Step 2: Rewrite the Install section**

```markdown
## Install

### Claude Code
/plugin marketplace add kschuster1/handoff
/plugin install handoff@claude-toolkit

### Codex
codex plugin marketplace add kschuster1/handoff --ref release
# then install handoff from the Codex plugin UI

### Gemini (script)
./install.sh --harness gemini      # detects ~/.gemini and wires the SessionStart hook
```

Both Claude and Codex install the lean `release` branch — only runtime files land on disk; the harness manages the install dir and uninstall.

- [ ] **Step 3: Rewrite the Uninstall section**

```markdown
## Uninstall
- **Claude Code:** `/plugin uninstall handoff@claude-toolkit`
- **Codex:** `codex plugin remove handoff` (or remove it in the Codex plugin UI)
- **Gemini:** remove `~/.gemini/commands/handoff.toml` and the handoff `SessionStart` entry from `~/.gemini/settings.json` (a `.bak` is alongside it).
```

(If the exact Codex remove command differs, note it as "see `codex plugin --help`" — do not invent a flag.)

- [ ] **Step 4: Add a maintainer note**

Document that `main` is the dev tree and `release` is generated by `scripts/build-release.sh`; releases are cut by running it, reviewing the worktree, and pushing `release`.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs(readme): native Codex+Claude plugin install, release-branch model"
```

---

### Task 10: Manual Codex smoke test + memory correction (no automation possible here)

**Files:**
- None in repo (manual verification + memory file update)

- [ ] **Step 1: Build and push the release branch**

```bash
bash scripts/build-release.sh
# review the printed worktree, then:
git -C <worktree> push -u origin release
```

- [ ] **Step 2: On a machine with Codex, install natively**

```bash
codex plugin marketplace add kschuster1/handoff --ref release
# install handoff via the Codex UI
```

- [ ] **Step 3: Verify nothing dev-only landed**

```bash
ls -R ~/.codex/plugins/*/handoff* | grep -iE 'docs|tests|superpowers' || echo "CLEAN"
```
Expected: `CLEAN`.

- [ ] **Step 4: Verify autosave events with the breadcrumb**

In a dirty git repo under Codex: `export HANDOFF_DEBUG=1`, start Codex, run a compact, exit. Then:
```bash
cat "${TMPDIR:-/tmp}/handoff-snapshot.log"
```
Expected: lines now show `event=PreCompact` (proving which event fired — no more guessing).

- [ ] **Step 5: Correct the project memory**

Update `~/.claude/projects/-Volumes-DevDisk-projects-handoff/memory/handoff-tool-project.md`: replace the unproven "Codex autosave VERIFIED — 2 fires (PreCompact+SessionEnd)" with the new install model (native plugin, release branch) and the corrected event set (no SessionEnd; PreCompact confirmed via `event=` breadcrumb). Update `MEMORY.md` pointer if the hook line changed.

---

### Task 11: Ignore the whole `.handoff/` directory

**Files:**
- Modify: `core/handoff-snapshot.sh` (gitignore line `.handoff/AUTOSAVE.md` → `.handoff/`)
- Modify: `core/handoff.md` (WRITE flow: add a gitignore-ensure step)
- Test: `tests/snapshot_test.sh` (update the existing gitignore assertion)

- [ ] **Step 1: Update the failing assertion in `tests/snapshot_test.sh`**

Find its current `.handoff/AUTOSAVE.md` gitignore assertion and change the expected line to `.handoff/`:

```bash
assert_contains "$(cat "$repo/.gitignore" 2>/dev/null)" ".handoff/" "snapshot ignores whole .handoff/ dir"
```

(Keep the "not duplicated on second snapshot" assertion; just update the matched string to `.handoff/`.)

- [ ] **Step 2: Run the test, verify it fails**

Run: `bash tests/snapshot_test.sh`
Expected: the gitignore assertion FAILs (script still writes `.handoff/AUTOSAVE.md`).

- [ ] **Step 3: Update `core/handoff-snapshot.sh`**

Replace the existing gitignore block:

```bash
GI="$CWD/.gitignore"
if ! { [ -f "$GI" ] && grep -qxF '.handoff/AUTOSAVE.md' "$GI"; }; then
  printf '.handoff/AUTOSAVE.md\n' >> "$GI"
```

with:

```bash
GI="$CWD/.gitignore"
if ! { [ -f "$GI" ] && grep -qxF '.handoff/' "$GI"; }; then
  printf '.handoff/\n' >> "$GI"
```

(Leave the closing `fi` and surrounding lines intact.)

- [ ] **Step 4: Add a gitignore-ensure step to `core/handoff.md` WRITE flow**

In the WRITE flow, before "### 6. Final confirm + write", add a numbered step:

```markdown
### 5b. Ensure `.handoff/` is gitignored
Before writing, make sure the project `.gitignore` contains a `.handoff/` line (add it if
absent — idempotent). Handoff files are local-by-default and should not be committed.
```

Then re-sync the command copies (Task 1 of cmd_sync applies): `cp core/handoff.md commands/handoff.md`.

- [ ] **Step 5: Run the suite, verify green**

Run: `bash tests/run.sh`
Expected: `snapshot_test.sh` and `cmd_sync_test.sh` pass; `0 failed` overall.

- [ ] **Step 6: Commit**

```bash
git add core/handoff-snapshot.sh core/handoff.md commands/handoff.md tests/snapshot_test.sh
git commit -m "feat(gitignore): ignore the whole .handoff/ dir, not just AUTOSAVE.md"
```

---

### Task 12: Silent one-time legacy migration in the loader

**Files:**
- Modify: `core/handoff-loader.sh` (add migration helpers + call site)
- Test: `tests/migrate_test.sh`

Migrates a legacy `./.ai/HANDOFF.md` or `./.claude/HANDOFF.md` into `./.handoff/HANDOFF.md`.
One-time (won't fire once `.handoff/HANDOFF.md` exists), reversible (legacy → `.bak`, memory
files backed up), and crash-proof (errexit disabled around the call so guards work).

- [ ] **Step 1: Write the failing test**

Create `tests/migrate_test.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

run_loader() { # project_dir
  printf '{"cwd":"%s"}' "$1" | bash "$ROOT/core/handoff-loader.sh" claude >/dev/null 2>&1 || true
}

# --- migrates .ai/HANDOFF.md, strips stale CLAUDE.md ref, ignores .handoff/ ---
p=$(mktemp -d)
mkdir -p "$p/.ai"
printf -- '---\nsummary: legacy\nresume: do x\n---\n# Handoff\nold\n' > "$p/.ai/HANDOFF.md"
printf 'project notes\n<!-- handoff-pointer --> read .ai/HANDOFF.md first\nkeep me\n' > "$p/CLAUDE.md"
run_loader "$p"
assert_eq "$([ -f "$p/.handoff/HANDOFF.md" ] && echo y || echo n)" "y" "migrated to .handoff/HANDOFF.md"
assert_contains "$(cat "$p/.handoff/HANDOFF.md")" "summary: legacy" "migrated content preserved"
assert_eq "$([ -f "$p/.ai/HANDOFF.md.bak" ] && echo y || echo n)" "y" "legacy renamed to .bak"
assert_eq "$([ -f "$p/.ai/HANDOFF.md" ] && echo y || echo n)" "n" "legacy original removed"
assert_contains "$(cat "$p/.gitignore")" ".handoff/" ".handoff/ gitignored"
assert_not_contains "$(cat "$p/CLAUDE.md")" "handoff-pointer" "stale pointer line stripped"
assert_contains "$(cat "$p/CLAUDE.md")" "keep me" "non-handoff CLAUDE.md lines preserved"
assert_eq "$([ -f "$p/CLAUDE.md.bak" ] && echo y || echo n)" "y" "CLAUDE.md backed up before edit"
rm -rf "$p"

# --- does NOT fire when a current handoff already exists ---
q=$(mktemp -d)
mkdir -p "$q/.ai" "$q/.handoff"
printf 'legacy\n' > "$q/.ai/HANDOFF.md"
printf -- '---\nsummary: current\n---\n' > "$q/.handoff/HANDOFF.md"
run_loader "$q"
assert_contains "$(cat "$q/.handoff/HANDOFF.md")" "summary: current" "existing handoff untouched"
assert_eq "$([ -f "$q/.ai/HANDOFF.md.bak" ] && echo y || echo n)" "n" "no migration when current handoff exists"
rm -rf "$q"

# --- prefers .ai over .claude; .claude path also works ---
r=$(mktemp -d)
mkdir -p "$r/.claude"
printf 'claudelegacy\n' > "$r/.claude/HANDOFF.md"
run_loader "$r"
assert_eq "$([ -f "$r/.handoff/HANDOFF.md" ] && echo y || echo n)" "y" ".claude/HANDOFF.md migrates too"
rm -rf "$r"
finish
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `bash tests/migrate_test.sh`
Expected: FAILs (loader has no migration yet).

- [ ] **Step 3: Add migration helpers to `core/handoff-loader.sh`**

Insert after the `AUTOSAVE="$HDIR/AUTOSAVE.md"` line (after line 22), before the `emit()` function:

```bash
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
```

- [ ] **Step 4: Add the call site (errexit-safe)**

Immediately after the helper definitions (still before `emit()`), add:

```bash
# Run migration with errexit OFF so the internal `[ -f ] && ...` guards can't abort the loader.
set +e
migrate_legacy_handoff "$CWD"
set -e
```

- [ ] **Step 5: Run the test, verify it passes**

Run: `bash tests/migrate_test.sh`
Expected: all `ok:`, `0 failed`.

- [ ] **Step 6: Run the full suite**

Run: `bash tests/run.sh`
Expected: `0 failed` overall (migration must not disturb existing loader tests).

- [ ] **Step 7: Commit**

```bash
git add core/handoff-loader.sh tests/migrate_test.sh
git commit -m "feat(loader): silent one-time reversible legacy handoff migration"
```

---

## Self-Review

**Spec coverage:**
- Distribution / dual plugin / release branch → Tasks 2,3,4,7 (+9 docs). ✓
- Per-harness hook files, no default hooks.json → Task 1. ✓
- Autosave event correctness (no SessionEnd; event-name breadcrumb; re-verify) → Tasks 1 (codex.json), 5 (breadcrumb), 10 (re-verify). ✓
- install.sh → Gemini-only → Task 6. ✓
- Tests (codex manifest, dual-manifest, no default hooks.json, build allowlist; retire codex install tests) → Tasks 1,2,3,7,6,8. ✓
- README → Task 9. ✓
- Memory correction → Task 10. ✓
- Ignore whole `.handoff/` dir (spec §7a) → Task 11. ✓
- Silent one-time reversible legacy migration, `.ai/`+`.claude/`, strip stale memory refs (spec §7b) → Task 12. ✓

**Placeholder scan:** Task 5's test wiring and Task 9's Codex-remove command are the only soft spots; both are flagged to mirror existing patterns / avoid inventing flags rather than left as "TODO". No bare TODO/TBD remain.

**Type/name consistency:** `hooks/claude.json` + `hooks/codex.json`, `HANDOFF_EVENT`, `HANDOFF_RELEASE_STAGE`, plugin name `handoff`, ref `release`, repo `kschuster1/handoff` — used consistently across tasks and tests.

**Open item from spec (Codex snapshot event set):** plan wires `PreCompact` only. If Task 10's live test shows compaction doesn't cover the "session ended without compact" case, add `Stop` (or a documented session-end event) in a follow-up — not blocking the redesign.
