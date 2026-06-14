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

# resolve {{HANDOFF_ROOT}} in a template file → stdout (literal replace; path-char safe)
render() {
  awk -v root="$ROOT" '
    { s="{{HANDOFF_ROOT}}";
      while ((p=index($0,s))>0) { $0=substr($0,1,p-1) root substr($0,p+length(s)) }
      print }' "$1"
}

log() { printf '  %s\n' "$1"; }

# Merge every event in a template's top-level `hooks` object into a (possibly pre-existing)
# config WITHOUT clobbering the user's other hooks/settings. All three harnesses nest events
# under a top-level `hooks` object (Claude/Codex hooks.json, Gemini settings.json). For each
# event the template defines, we drop existing handoff-owned entries (serialized-entry contains
# `core/handoff-`, matching both the loader and the snapshot script) and append ours — so the
# merge is idempotent and only ever touches handoff's own entries. Works for both Claude/Codex-
# nested entries ({hooks:[{command}]}) and Gemini-flat entries ({command}). Backs up to .bak.
merge_hooks() { # template_path dest_path
  local tmpl="$1" dest="$2" rendered rtmp
  rendered=$(render "$tmpl")
  if [ -f "$dest" ] && jq -e . "$dest" >/dev/null 2>&1; then
    cp "$dest" "$dest.bak"
    rtmp=$(mktemp)
    printf '%s' "$rendered" > "$rtmp"
    jq --slurpfile tmpl "$rtmp" '
      ($tmpl[0].hooks) as $new
      | .hooks = (.hooks // {})
      | reduce ($new | keys[]) as $ev (.;
          .hooks[$ev] = (
            (((.hooks[$ev]) // [])
              | map(select((tojson | contains("core/handoff-")) | not)))
            + $new[$ev]))
    ' "$dest" > "$dest.tmp" && mv "$dest.tmp" "$dest"
    rm -f "$rtmp"
    log "merged hooks into existing $(basename "$dest") (backup: $(basename "$dest").bak)"
  else
    printf '%s\n' "$rendered" > "$dest"
    log "wrote $(basename "$dest")"
  fi
}

# ── Codex ────────────────────────────────────────────────────
if want codex && [ -d "$HOME_DIR/.codex" ]; then
  echo "Codex detected → $HOME_DIR/.codex"
  mkdir -p "$HOME_DIR/.codex/prompts"
  cp "$ROOT/core/handoff.md" "$HOME_DIR/.codex/prompts/handoff.md"
  merge_hooks "$ROOT/adapters/codex/hooks.json" "$HOME_DIR/.codex/hooks.json"
  log "prompt + SessionStart hook installed"
fi

# ── Gemini ───────────────────────────────────────────────────
if want gemini && [ -d "$HOME_DIR/.gemini" ]; then
  echo "Gemini detected → $HOME_DIR/.gemini"
  mkdir -p "$HOME_DIR/.gemini/commands"
  render "$ROOT/adapters/gemini/commands/handoff.toml" > "$HOME_DIR/.gemini/commands/handoff.toml"
  merge_hooks "$ROOT/adapters/gemini/settings.json" "$HOME_DIR/.gemini/settings.json"
  log "command + SessionStart hook installed"
fi

# ── Claude Code ──────────────────────────────────────────────
# Claude is normally installed via the plugin marketplace, not this script.
# We only print guidance unless the user clearly uses ~/.claude.
if want claude && [ -d "$HOME_DIR/.claude" ]; then
  echo "Claude Code detected → install via marketplace for the managed path:"
  log "/plugin marketplace add $ROOT"
  log "/plugin install handoff@claude-toolkit"
fi

# ── Optional: autosave hooks (mechanical snapshot on clear/compact) ──
# Claude Code gets these built into the plugin's hooks.json (SessionEnd + PreCompact), so
# nothing to do there. For Codex/Gemini we wire them here — but their hook-event support is
# UNVERIFIED (assumed from the SessionStart adapter pattern), so this path is EXPERIMENTAL.
if [ "$AUTOSAVE" -eq 1 ]; then
  echo "Autosave snapshot hooks (Claude Code: built into the plugin):"
  log "EXPERIMENTAL for Codex/Gemini — event support is unverified; safe to remove via the .bak backup."
  if want codex && [ -d "$HOME_DIR/.codex" ]; then
    merge_hooks "$ROOT/adapters/codex/hooks-autosave.json" "$HOME_DIR/.codex/hooks.json"
    log "codex: snapshot hooks (SessionEnd + PreCompact) wired"
  fi
  if want gemini && [ -d "$HOME_DIR/.gemini" ]; then
    merge_hooks "$ROOT/adapters/gemini/settings-autosave.json" "$HOME_DIR/.gemini/settings.json"
    log "gemini: snapshot hook (AfterAgent) wired"
  fi
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
