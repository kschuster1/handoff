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
