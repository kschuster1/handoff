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

WT="$(mktemp -d)"
git worktree add --force -B release "$WT" >/dev/null
( cd "$WT" && git rm -rqf . >/dev/null 2>&1 || true )
stage_into "$WT"
( cd "$WT" && git add -A && git commit -q -m "build: release $(jq -r .version "$ROOT/.claude-plugin/plugin.json")" || echo "no changes" )
echo "Release built in worktree: $WT"
echo "Review, then publish:  git -C \"$WT\" push -u origin release"
echo "Cleanup when done:      git worktree remove \"$WT\""
