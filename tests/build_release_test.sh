#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT="$(dirname "$0")/.."

stage=$(mktemp -d)
( cd "$ROOT" && HANDOFF_RELEASE_STAGE="$stage" bash scripts/build-release.sh ) >/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "build-release stage mode exits 0"

# Repo-root files (Claude plugin + marketplaces + shared assets)
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json \
         .agents/plugins/marketplace.json \
         hooks/claude.json \
         core/handoff-loader.sh core/handoff-snapshot.sh core/handoff.md \
         commands/handoff.md README.md LICENSE; do
  assert_eq "$([ -f "$stage/$f" ] && echo y || echo n)" "y" "release includes $f"
done

# Self-contained Codex plugin bundle under plugins/handoff/ — hook is hooks.json at bundle ROOT
# (Codex auto-discovers it), not a nested hooks/ dir.
for f in plugins/handoff/.codex-plugin/plugin.json \
         plugins/handoff/hooks.json \
         plugins/handoff/core/handoff-loader.sh \
         plugins/handoff/core/handoff-snapshot.sh \
         plugins/handoff/core/handoff.md \
         plugins/handoff/commands/handoff.md; do
  assert_eq "$([ -f "$stage/$f" ] && echo y || echo n)" "y" "codex bundle includes $f"
done

# Codex plugin manifest + codex hook file must NOT sit at the repo root (only in the bundle)
assert_eq "$([ -f "$stage/.codex-plugin/plugin.json" ] && echo y || echo n)" "n" "no root .codex-plugin (bundle only)"
assert_eq "$([ -f "$stage/hooks/codex.json" ] && echo y || echo n)" "n" "no root hooks/codex.json (bundle only)"
# the bundle hook is named hooks.json (root), not nested
assert_eq "$([ -f "$stage/plugins/handoff/hooks/codex.json" ] && echo y || echo n)" "n" "no nested hooks/codex.json in bundle"

# Dev-only files must NOT ship
assert_eq "$([ -d "$stage/docs" ] && echo y || echo n)" "n" "release excludes docs/"
assert_eq "$([ -d "$stage/tests" ] && echo y || echo n)" "n" "release excludes tests/"
assert_eq "$([ -f "$stage/hooks/hooks.json" ] && echo y || echo n)" "n" "release has no default hooks.json"
assert_eq "$([ -d "$stage/.git" ] && echo y || echo n)" "n" "release excludes .git"
rm -rf "$stage"
finish
