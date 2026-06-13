#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
SNAP="$(dirname "$0")/../core/handoff-snapshot.sh"

newrepo() { # -> echoes path to a fresh git repo
  local d; d=$(mktemp -d)
  ( cd "$d" && git init -q && git config user.email t@t.t && git config user.name t \
      && echo hi > a.txt && git add a.txt && git commit -qm init ) >/dev/null
  echo "$d"
}

# clean tree, no commits ahead → no snapshot written
R1=$(newrepo)
bash "$SNAP" "$R1"
assert_eq "$([ -f "$R1/.handoff/AUTOSAVE.md" ] && echo yes || echo no)" "no" "clean repo → no snapshot"

# dirty tree → snapshot written with frontmatter
R2=$(newrepo)
( cd "$R2" && echo change >> a.txt && echo new > b.txt )
bash "$SNAP" "$R2"
assert_eq "$([ -f "$R2/.handoff/AUTOSAVE.md" ] && echo yes || echo no)" "yes" "dirty repo → snapshot written"
body=$(cat "$R2/.handoff/AUTOSAVE.md")
assert_contains "$body" "branch:" "snapshot has branch frontmatter"
assert_contains "$body" "dirty:" "snapshot has dirty count"
assert_contains "$body" "commits:" "snapshot has commits-ahead count"
# size cap: under 8KB comfortably
sz=$(wc -c < "$R2/.handoff/AUTOSAVE.md" | tr -d ' ')
assert_eq "$([ "$sz" -lt 8192 ] && echo ok || echo big)" "ok" "snapshot under 8KB"

# never clobbers a manual handoff
R3=$(newrepo)
( cd "$R3" && echo change >> a.txt )
mkdir -p "$R3/.handoff"; echo "MANUAL" > "$R3/.handoff/HANDOFF.md"
bash "$SNAP" "$R3"
assert_eq "$([ -f "$R3/.handoff/AUTOSAVE.md" ] && echo yes || echo no)" "no" "manual handoff present → snapshot skipped"

# commitless repo (git init + dirty, no commit yet) must not crash; AUTOSAVE well-formed
R4=$(mktemp -d)
( cd "$R4" && git init -q && git config user.email t@t.t && git config user.name t && echo x > a.txt ) >/dev/null
bash "$SNAP" "$R4"; rc=$?
assert_eq "$rc" "0" "commitless dirty repo → snapshot exits 0 (no set -e crash)"
b=$(cat "$R4/.handoff/AUTOSAVE.md" 2>/dev/null || echo "")
assert_contains "$b" "branch:" "commitless snapshot still has frontmatter"
# fenced code blocks balanced (even number of ``` fences)
fences=$(grep -c '```' "$R4/.handoff/AUTOSAVE.md" 2>/dev/null || echo 0)
assert_eq "$((fences % 2))" "0" "commitless snapshot has balanced code fences (not truncated)"

finish
