#!/usr/bin/env bash
# runs every *_test.sh in tests/, fails if any fails
set -e
cd "$(dirname "$0")"
rc=0
for t in ./*_test.sh; do
  [ -e "$t" ] || continue
  echo "=== $t ==="
  bash "$t" || rc=1
done
exit $rc
