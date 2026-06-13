#!/usr/bin/env bash
# tiny assertion lib — source it, then call asserts; call finish at end.
PASS=0; FAIL=0
_red() { printf '\033[31m%s\033[0m\n' "$1"; }
_grn() { printf '\033[32m%s\033[0m\n' "$1"; }

assert_contains() { # haystack needle msg
  if printf '%s' "$1" | grep -qF -- "$2"; then PASS=$((PASS+1)); _grn "ok: $3";
  else FAIL=$((FAIL+1)); _red "FAIL: $3"; _red "  expected to contain: $2"; fi
}
assert_not_contains() { # haystack needle msg
  if printf '%s' "$1" | grep -qF -- "$2"; then FAIL=$((FAIL+1)); _red "FAIL: $3"; _red "  expected NOT to contain: $2";
  else PASS=$((PASS+1)); _grn "ok: $3"; fi
}
assert_eq() { # actual expected msg
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); _grn "ok: $3";
  else FAIL=$((FAIL+1)); _red "FAIL: $3"; _red "  got:[$1] want:[$2]"; fi
}
assert_json_field() { # json jq-path expected msg
  local got; got=$(printf '%s' "$1" | jq -r "$2" 2>/dev/null || echo "<jq-error>")
  assert_eq "$got" "$3" "$4"
}
finish() { printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]; }
