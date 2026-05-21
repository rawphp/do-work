#!/usr/bin/env bash
# Tests for lib/drain-classify.sh
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
CLASSIFIER="$LIB_DIR/drain-classify.sh"

FAILED=0
CASES=0
CURRENT_CASE=""

fail() {
  echo "FAIL [$CURRENT_CASE]: $*" >&2
  FAILED=$((FAILED + 1))
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}

run_classify() {
  # $1 = stdin content (use empty string for empty stdin)
  local input="$1"
  local out_file
  out_file="$(mktemp -t drain-classify-test.XXXXXX)"
  printf '%s' "$input" | "$CLASSIFIER" > "$out_file" 2>/dev/null
  CL_RC=$?
  CL_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  rm -f "$out_file"
}

# ----------------------------------------------------------------------
# Case 1: empty stdin → truly-empty
# ----------------------------------------------------------------------
CURRENT_CASE="empty-stdin"
CASES=$((CASES + 1))
run_classify ""
assert_eq "0" "$CL_RC" "$CURRENT_CASE rc"
assert_eq "truly-empty" "$CL_STDOUT" "$CURRENT_CASE label"

# ----------------------------------------------------------------------
# Case 2: only noise (no recognised prefixes) → truly-empty
# ----------------------------------------------------------------------
CURRENT_CASE="noise-only"
CASES=$((CASES + 1))
run_classify "some random log line
another irrelevant line
"
assert_eq "0" "$CL_RC" "$CURRENT_CASE rc"
assert_eq "truly-empty" "$CL_STDOUT" "$CURRENT_CASE label"

# ----------------------------------------------------------------------
# Case 3: dep: only → deps-blocked
# ----------------------------------------------------------------------
CURRENT_CASE="dep-only"
CASES=$((CASES + 1))
run_classify "dep:REQ-005
"
assert_eq "0" "$CL_RC" "$CURRENT_CASE rc"
assert_eq "deps-blocked" "$CL_STDOUT" "$CURRENT_CASE label"

# ----------------------------------------------------------------------
# Case 4: overlap: only → overlap-blocked
# ----------------------------------------------------------------------
CURRENT_CASE="overlap-only"
CASES=$((CASES + 1))
run_classify "overlap:REQ-007
"
assert_eq "0" "$CL_RC" "$CURRENT_CASE rc"
assert_eq "overlap-blocked" "$CL_STDOUT" "$CURRENT_CASE label"

# ----------------------------------------------------------------------
# Case 5: scope: only → scope-blocked
# ----------------------------------------------------------------------
CURRENT_CASE="scope-only"
CASES=$((CASES + 1))
run_classify "scope:REQ-010
"
assert_eq "0" "$CL_RC" "$CURRENT_CASE rc"
assert_eq "scope-blocked" "$CL_STDOUT" "$CURRENT_CASE label"

# ----------------------------------------------------------------------
# Case 6: dep + overlap → overlap wins
# ----------------------------------------------------------------------
CURRENT_CASE="dep-and-overlap"
CASES=$((CASES + 1))
run_classify "dep:REQ-005
overlap:REQ-007
"
assert_eq "0" "$CL_RC" "$CURRENT_CASE rc"
assert_eq "overlap-blocked" "$CL_STDOUT" "$CURRENT_CASE label"

# ----------------------------------------------------------------------
# Case 7: dep + scope → deps-blocked (deps beats scope)
# ----------------------------------------------------------------------
CURRENT_CASE="dep-and-scope"
CASES=$((CASES + 1))
run_classify "scope:REQ-010
dep:REQ-005
"
assert_eq "0" "$CL_RC" "$CURRENT_CASE rc"
assert_eq "deps-blocked" "$CL_STDOUT" "$CURRENT_CASE label"

# ----------------------------------------------------------------------
# Case 8: overlap + scope → overlap-blocked
# ----------------------------------------------------------------------
CURRENT_CASE="overlap-and-scope"
CASES=$((CASES + 1))
run_classify "scope:REQ-010
overlap:REQ-007
"
assert_eq "0" "$CL_RC" "$CURRENT_CASE rc"
assert_eq "overlap-blocked" "$CL_STDOUT" "$CURRENT_CASE label"

# ----------------------------------------------------------------------
# Case 9: all three present → overlap-blocked
# ----------------------------------------------------------------------
CURRENT_CASE="all-three"
CASES=$((CASES + 1))
run_classify "scope:REQ-010
dep:REQ-005
overlap:REQ-007
"
assert_eq "0" "$CL_RC" "$CURRENT_CASE rc"
assert_eq "overlap-blocked" "$CL_STDOUT" "$CURRENT_CASE label"

# ----------------------------------------------------------------------
# Case 10: mixed with noise lines → still classified by prefixes
# ----------------------------------------------------------------------
CURRENT_CASE="mixed-with-noise"
CASES=$((CASES + 1))
run_classify "considering REQ-005
dep:REQ-005
some irrelevant chatter
"
assert_eq "0" "$CL_RC" "$CURRENT_CASE rc"
assert_eq "deps-blocked" "$CL_STDOUT" "$CURRENT_CASE label"

# ----------------------------------------------------------------------
# Case 11: prefix must be at start of line — substring 'dep:' mid-line ignored
# ----------------------------------------------------------------------
CURRENT_CASE="prefix-line-anchored"
CASES=$((CASES + 1))
run_classify "considering dep:REQ-005 not at line start
random scope:foo also mid-line
"
assert_eq "0" "$CL_RC" "$CURRENT_CASE rc"
assert_eq "truly-empty" "$CL_STDOUT" "$CURRENT_CASE label"

# ----------------------------------------------------------------------
# Case 12: multiple deps lines → deps-blocked (no overlap)
# ----------------------------------------------------------------------
CURRENT_CASE="multiple-deps"
CASES=$((CASES + 1))
run_classify "dep:REQ-005
dep:REQ-006
dep:REQ-007
"
assert_eq "0" "$CL_RC" "$CURRENT_CASE rc"
assert_eq "deps-blocked" "$CL_STDOUT" "$CURRENT_CASE label"

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------
echo ""
echo "Ran $CASES cases. Failures: $FAILED"
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
