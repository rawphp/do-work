#!/usr/bin/env bash
# Tests for lib/score-coverage.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/score-coverage.sh"

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

run_score() {
  OUT="$(bash "$SCRIPT" "$@" 2>/dev/null)"
  RC=$?
}

# --- Base coverage formula ---------------------------------------------------

CURRENT_CASE="full-coverage-no-gaps"
CASES=$((CASES + 1))
run_score --full 10 --partial 0 --missing 0
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "100" "$OUT" "$CURRENT_CASE output"

CURRENT_CASE="partial-counts-half"
CASES=$((CASES + 1))
# (8 + 0.5*1)/10 * 100 = 85, no gaps
run_score --full 8 --partial 1 --missing 1
assert_eq "85" "$OUT" "$CURRENT_CASE output"

CURRENT_CASE="rounds-to-integer"
CASES=$((CASES + 1))
# (2 + 0.5*0)/3 * 100 = 66.66... -> 67
run_score --full 2 --partial 0 --missing 1
assert_eq "67" "$OUT" "$CURRENT_CASE output"

# --- Acceptance criterion: 8/1/1 + 2 layer gaps -> 65 ------------------------

CURRENT_CASE="ac-8-1-1-two-layer-gaps"
CASES=$((CASES + 1))
# base 85 - (2 * 10) = 65
run_score --full 8 --partial 1 --missing 1 --layer-gaps 2
assert_eq "65" "$OUT" "$CURRENT_CASE output"

# --- Per-category caps -------------------------------------------------------

CURRENT_CASE="ideate-cap-20"
CASES=$((CASES + 1))
# 10 ideate flags * 5 = 50, capped at 20. base 100 - 20 = 80
run_score --full 10 --partial 0 --missing 0 --ideate-flags 10
assert_eq "80" "$OUT" "$CURRENT_CASE output"

CURRENT_CASE="layer-cap-30"
CASES=$((CASES + 1))
# 10 layer gaps * 10 = 100, capped at 30. base 100 - 30 = 70
run_score --full 10 --partial 0 --missing 0 --layer-gaps 10
assert_eq "70" "$OUT" "$CURRENT_CASE output"

CURRENT_CASE="integration-cap-25"
CASES=$((CASES + 1))
# 10 integration gaps * 5 = 50, capped at 25. base 100 - 25 = 75
run_score --full 10 --partial 0 --missing 0 --integration-gaps 10
assert_eq "75" "$OUT" "$CURRENT_CASE output"

CURRENT_CASE="partial-conf-cap-15"
CASES=$((CASES + 1))
# 10 partial-confidence gaps * 3 = 30, capped at 15. base 100 - 15 = 85
run_score --full 10 --partial 0 --missing 0 --partial-conf-gaps 10
assert_eq "85" "$OUT" "$CURRENT_CASE output"

CURRENT_CASE="dangling-cap-20"
CASES=$((CASES + 1))
# Acceptance criterion: 10 dangling deps deduct 20, not 50.
# base 100 - 20 = 80
run_score --full 10 --partial 0 --missing 0 --dangling-deps 10
assert_eq "80" "$OUT" "$CURRENT_CASE output"

CURRENT_CASE="path-unit-cap-20"
CASES=$((CASES + 1))
# 10 path-unit gaps * 5 = 50, capped at 20. base 100 - 20 = 80
run_score --full 10 --partial 0 --missing 0 --path-unit-gaps 10
assert_eq "80" "$OUT" "$CURRENT_CASE output"

# --- Caps are independent (each category capped on its own) ------------------

CURRENT_CASE="caps-applied-per-category"
CASES=$((CASES + 1))
# ideate 10*5->cap20, layer 10*10->cap30 = 50 total. base 100 - 50 = 50
run_score --full 10 --partial 0 --missing 0 --ideate-flags 10 --layer-gaps 10
assert_eq "50" "$OUT" "$CURRENT_CASE output"

CURRENT_CASE="under-cap-uses-actual"
CASES=$((CASES + 1))
# 2 ideate flags * 5 = 10 (under cap). base 100 - 10 = 90
run_score --full 10 --partial 0 --missing 0 --ideate-flags 2
assert_eq "90" "$OUT" "$CURRENT_CASE output"

# --- Floor at 0 --------------------------------------------------------------

CURRENT_CASE="floor-at-zero"
CASES=$((CASES + 1))
# base low + every cap maxed should never go negative.
# base (1/10*100)=10; deductions 20+30+25+15+20+20 = 130 -> floor 0
run_score --full 1 --partial 0 --missing 9 \
  --ideate-flags 99 --layer-gaps 99 --integration-gaps 99 \
  --partial-conf-gaps 99 --dangling-deps 99 --path-unit-gaps 99
assert_eq "0" "$OUT" "$CURRENT_CASE output"

# --- Edge: zero requirements -------------------------------------------------

CURRENT_CASE="zero-total-requirements"
CASES=$((CASES + 1))
# No requirements at all -> treat as 0 (cannot divide by zero); non-error.
run_score --full 0 --partial 0 --missing 0
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "0" "$OUT" "$CURRENT_CASE output"

# --- Defaults: omitted gap flags count as zero -------------------------------

CURRENT_CASE="omitted-flags-default-zero"
CASES=$((CASES + 1))
run_score --full 5 --partial 0 --missing 5
assert_eq "50" "$OUT" "$CURRENT_CASE output"

echo ""
echo "score-coverage tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
