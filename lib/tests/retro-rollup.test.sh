#!/usr/bin/env bash
# Tests for lib/retro-rollup.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.
#
# Contract under test (docs/design/retro-learning.md §5a):
#   runs=N
#   stop <shape-key> <reason>=<count>
#   stop_rate <shape-key>=<ratio>
#   escalation_rate=<ratio>
#   escalation <shape-key>=<count>
#   footprint under=<r> over=<r> exact=<r>
#   footprint_missed <glob>=<count>
#   recurrence <event>:<shape> weighted=<w> raw=<n>
#
# Empty-state (§2e): prints `runs=0` and exits 0.
# Malformed entries (REQ-217 task): skipped with a warning line, never crash.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/retro-rollup.sh"

FAILED=0
CASES=0
CURRENT_CASE=""

# Fixed "now" so recency weighting (§2d) is deterministic. Fixture ended_at
# timestamps below straddle this date's 30-day window on purpose.
RETRO_NOW="2026-06-12T00:00:00Z"

fail() {
  echo "FAIL [$CURRENT_CASE]: $*" >&2
  FAILED=$((FAILED + 1))
}

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"
  case "$haystack" in
    *"$needle"*) : ;;
    *) fail "$label: expected substring '$needle' in: $haystack" ;;
  esac
}

assert_not_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"
  case "$haystack" in
    *"$needle"*) fail "$label: did not expect substring '$needle' in: $haystack" ;;
    *) : ;;
  esac
}

assert_rc() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$label: expected rc '$expected', got '$actual'"
  fi
}

setup_fixture() {
  TMP="$(mktemp -d -t retro-rollup-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/runs" "$TMP/.do-work/archive" "$TMP/.do-work/working"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

# write_req <path> <id> <ur> <layer> <files-csv> <ac-lines>
# <ac-lines> is the number of "- [ ]" acceptance criteria to emit.
write_req() {
  local path="$1" id="$2" ur="$3" layer="$4" files="$5" ac="$6"
  {
    echo "# $id: Test"
    echo ""
    echo "**UR:** $ur"
    echo "**Status:** done"
    echo "**Layer:** $layer"
    echo "**Files:** $files"
    echo "**Depends on:**"
    echo ""
    echo "## Acceptance Criteria"
    echo ""
    local i=1
    while [ "$i" -le "$ac" ]; do
      echo "- [ ] criterion $i"
      i=$((i + 1))
    done
  } > "$path"
}

# write_run <path> <req> <ur> <model> <result> <review> <changed-csv> <ended_at>
write_run() {
  local path="$1" req="$2" ur="$3" model="$4" result="$5" review="$6" changed="$7" ended="$8"
  {
    echo "run_id: $(basename "$path" .yml)"
    echo "req: $req"
    echo "ur: $ur"
    echo "model: \"$model\""
    echo "result: \"$result\""
    echo "review_outcome: \"$review\""
    echo "proof_status: \"proven\""
    echo "started_at: \"$ended\""
    echo "ended_at: \"$ended\""
    echo "changed_files:"
    local f
    local IFS=,
    for f in $changed; do
      [ -z "$f" ] && continue
      echo "  - \"$f\""
    done
  } > "$path"
}

run_script() {
  OUT="$(cd "$TMP" && RETRO_NOW="$RETRO_NOW" bash "$SCRIPT")"
  RC=$?
}

# ---------------------------------------------------------------------------
# Case 1: normal — >=3 ledger entries, all pattern sections present
# ---------------------------------------------------------------------------
CURRENT_CASE="normal-all-sections"
CASES=$((CASES + 1))
setup_fixture

# REQ-001: lib, 2 ACs (<=2), 1 file. Declared lib/a.sh; changed lib/a.sh + lib/a.test.sh -> under-prediction.
write_req "$TMP/.do-work/archive/REQ-001-a.md" "REQ-001" "UR-001" "lib" "lib/a.sh" 2
write_run "$TMP/.do-work/runs/RUN-001.yml" "REQ-001" "UR-001" "sonnet" "done" "passed" "lib/a.sh,lib/a.test.sh" "2026-06-11T00:00:00Z"

# REQ-002: agents, 5 ACs (>4), 4 files (>3). sonnet then opus -> escalation. verification-failing.
write_req "$TMP/.do-work/archive/REQ-002-b.md" "REQ-002" "UR-001" "agents" "agents/a.md, agents/b.md, agents/c.md, agents/d.md" 5
write_run "$TMP/.do-work/runs/RUN-002.yml" "REQ-002" "UR-001" "sonnet" "verification-failing" "not-run" "agents/a.md" "2026-06-11T00:00:00Z"
write_run "$TMP/.do-work/runs/RUN-003.yml" "REQ-002" "UR-001" "opus" "done" "passed" "agents/a.md,agents/b.md,agents/c.md,agents/d.md" "2026-06-11T00:00:00Z"

# REQ-003: agents, 5 ACs (>4), 4 files (>3). Same shape as REQ-002, also
# verification-failing -> recurrence. Stays on sonnet (no escalation) so only
# REQ-002 counts as escalated (§2b: a REQ with any opus row).
write_req "$TMP/.do-work/archive/REQ-003-c.md" "REQ-003" "UR-001" "agents" "agents/e.md, agents/f.md, agents/g.md, agents/h.md" 5
write_run "$TMP/.do-work/runs/RUN-004.yml" "REQ-003" "UR-001" "sonnet" "verification-failing" "not-run" "agents/e.md" "2026-06-11T00:00:00Z"

run_script
assert_rc 0 "$RC" "$CURRENT_CASE rc"

# runs= total ledger rows analyzed (4 rows across 3 REQs)
assert_contains "runs=4" "$OUT" "$CURRENT_CASE runs total"

# §2a stop-reason frequency by shape + stop_rate
assert_contains "stop lib/≤2AC/1file done=1" "$OUT" "$CURRENT_CASE stop lib done"
assert_contains "stop agents/>4AC/>3file verification-failing=2" "$OUT" "$CURRENT_CASE stop agents vfail"
assert_contains "stop_rate lib/≤2AC/1file=0.00" "$OUT" "$CURRENT_CASE stop_rate lib"
# agents shape: 3 rows (2 vfail + 1 done) -> 2 non-done / 3 = 0.67
assert_contains "stop_rate agents/>4AC/>3file=0.67" "$OUT" "$CURRENT_CASE stop_rate agents"

# §2b escalation — REQ-002 has an opus row -> 1 of 3 REQs escalated = 0.33
assert_contains "escalation_rate=0.33" "$OUT" "$CURRENT_CASE escalation_rate"
assert_contains "escalation agents/>4AC/>3file=1" "$OUT" "$CURRENT_CASE escalation shape"

# §2c footprint rates: REQ-001 under (test file not declared), REQ-002 exact, REQ-003 over (declared 4, changed 1)
assert_contains "footprint under=" "$OUT" "$CURRENT_CASE footprint line"
assert_contains "footprint_missed lib/a.test.sh=1" "$OUT" "$CURRENT_CASE footprint missed glob"

# §2d recurrence — verify-fail on agents/>4AC/>3file appears in 2 distinct REQs
assert_contains "recurrence verify-fail:agents/>4AC/>3file" "$OUT" "$CURRENT_CASE recurrence"
# Both rows ended 2026-06-11 (within 30d of NOW 2026-06-12) -> recency-weighted x2.
assert_contains "recurrence verify-fail:agents/>4AC/>3file weighted=4 raw=2" "$OUT" "$CURRENT_CASE recurrence weighting"
teardown_fixture

# ---------------------------------------------------------------------------
# Case 1b: recency weighting — an OLD recurrence (>30d) is NOT doubled
# ---------------------------------------------------------------------------
CURRENT_CASE="recency-old-not-doubled"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-020-a.md" "REQ-020" "UR-003" "lib" "lib/p.sh" 2
write_req "$TMP/.do-work/archive/REQ-021-b.md" "REQ-021" "UR-003" "lib" "lib/q.sh" 2
# Both ended well outside the 30-day window from NOW (2026-06-12).
write_run "$TMP/.do-work/runs/RUN-020.yml" "REQ-020" "UR-003" "sonnet" "verification-failing" "not-run" "lib/p.sh" "2026-01-01T00:00:00Z"
write_run "$TMP/.do-work/runs/RUN-021.yml" "REQ-021" "UR-003" "sonnet" "verification-failing" "not-run" "lib/q.sh" "2026-01-01T00:00:00Z"
run_script
assert_rc 0 "$RC" "$CURRENT_CASE rc"
# raw still 2, but weighted stays 2 (1x2) because neither is recent.
assert_contains "recurrence verify-fail:lib/≤2AC/1file weighted=2 raw=2" "$OUT" "$CURRENT_CASE old weighting"
teardown_fixture

# ---------------------------------------------------------------------------
# Case 2: empty — no runs/ dir contents -> runs=0, exit 0 (§2e)
# ---------------------------------------------------------------------------
CURRENT_CASE="empty-state"
CASES=$((CASES + 1))
setup_fixture
run_script
assert_rc 0 "$RC" "$CURRENT_CASE rc"
assert_contains "runs=0" "$OUT" "$CURRENT_CASE sentinel"
assert_not_contains "stop " "$OUT" "$CURRENT_CASE no stop lines"
teardown_fixture

# ---------------------------------------------------------------------------
# Case 2b: runs/ dir entirely absent -> still runs=0, exit 0
# ---------------------------------------------------------------------------
CURRENT_CASE="no-runs-dir"
CASES=$((CASES + 1))
setup_fixture
rm -rf "$TMP/.do-work/runs"
run_script
assert_rc 0 "$RC" "$CURRENT_CASE rc"
assert_contains "runs=0" "$OUT" "$CURRENT_CASE sentinel"
teardown_fixture

# ---------------------------------------------------------------------------
# Case 3: malformed entry -> skipped with a warning, never crash, exit 0
# ---------------------------------------------------------------------------
CURRENT_CASE="malformed-tolerated"
CASES=$((CASES + 1))
setup_fixture
# One good row...
write_req "$TMP/.do-work/archive/REQ-010-a.md" "REQ-010" "UR-002" "lib" "lib/x.sh" 2
write_run "$TMP/.do-work/runs/RUN-010.yml" "REQ-010" "UR-002" "sonnet" "done" "passed" "lib/x.sh" "2026-06-11T00:00:00Z"
# ...and one malformed row (no req field, garbage content).
printf 'this is not: valid: yaml\n\x00\x00garbage\n' > "$TMP/.do-work/runs/RUN-011.yml"
ERR="$(cd "$TMP" && RETRO_NOW="$RETRO_NOW" bash "$SCRIPT" 2>&1 1>/dev/null)"
run_script
assert_rc 0 "$RC" "$CURRENT_CASE rc (no crash)"
# The good row still counts.
assert_contains "runs=1" "$OUT" "$CURRENT_CASE good row counted"
# A warning naming the skipped file is emitted on stderr.
assert_contains "RUN-011" "$ERR" "$CURRENT_CASE warning names file"
assert_contains "skip" "$ERR" "$CURRENT_CASE warning says skip"
teardown_fixture

echo ""
echo "retro-rollup tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
