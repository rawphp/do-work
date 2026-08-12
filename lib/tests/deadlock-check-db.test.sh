#!/usr/bin/env bash
# Tests for dw-db deadlock-check (lib/dw-db.sh) — sqlite runtime-cycle diagnosis.
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.
#
# Acceptance criteria (REQ-019):
#   - cyclic deps table → dw-db deadlock-check reports a runtime-cycle diagnosis
#     (parity with lib/deadlock-check.sh's runtime-cycle case) with the cycle
#     path; exit 0 (stdout presence distinguishes, matching deadlock-check.sh).
#   - acyclic deps → no runtime-cycle (clean): empty stdout, exit 0.
#   - does NOT invoke lib/cycle-check.sh or glob REQ-*.md — uses REQ-017's
#     sqlite cycle_core directly. Proven behaviourally: every fixture below has
#     ONLY database rows (no .do-work/REQ-*.md files), so any detected cycle
#     must have been read from the deps table, not the markdown store.
#
# Cycles are built by direct INSERT into the deps junction (NOT via
# set-blocked-by, which rejects cycles after REQ-018).

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
DWDB="$LIB_DIR/dw-db.sh"

FAILED=0
CASES=0
CURRENT_CASE=""

fail() {
  echo "FAIL [$CURRENT_CASE]: $*" >&2
  FAILED=$((FAILED + 1))
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local needle="$1" haystack="$2" label="$3"
  case "$haystack" in
    *"$needle"*) : ;;
    *) fail "$label: expected substring '$needle' in '$haystack'" ;;
  esac
}

assert_not_contains() {
  local needle="$1" haystack="$2" label="$3"
  case "$haystack" in
    *"$needle"*) fail "$label: did not expect substring '$needle' in '$haystack'" ;;
  esac
}

setup_fixture() {
  TMP="$(mktemp -d -t deadlock-check-db-test.XXXXXX)"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

mkroot() {
  bash "$DWDB" ensure "$TMP" >/dev/null
}
mkur() {
  bash "$DWDB" create-ur "$TMP" --title "$1" --brief "$2"
}
mkreq() {
  bash "$DWDB" create-req "$TMP" --ur "$1" --title "$2"
}

# Insert a dep edge directly into deps (by slug → id subquery). Bypasses
# set-blocked-by on purpose so cycles can be constructed for detection tests.
add_dep() {
  local rs="$1" ds="$2"
  local db="$TMP/.do-work/work.db"
  sqlite3 "$db" "INSERT OR IGNORE INTO deps(req_id, depends_on_req_id) \
VALUES((SELECT id FROM reqs WHERE slug='$rs'), \
(SELECT id FROM reqs WHERE slug='$ds'));"
}

# run_check [args...] — runs deadlock-check against $TMP; sets CHK_RC / CHK_STDOUT.
run_check() {
  local out_file="$TMP/.stdout.$$"
  local err_file="$TMP/.stderr.$$"
  bash "$DWDB" deadlock-check "$TMP" "$@" >"$out_file" 2>"$err_file"
  CHK_RC=$?
  CHK_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  CHK_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$out_file" "$err_file"
}

# Assert the current fixture has NO markdown REQ files — so any cycle detected
# had to come from the sqlite deps table, not a markdown glob (AC3).
assert_no_markdown_reqs() {
  local found
  found="$(find "$TMP/.do-work" -maxdepth 2 -name 'REQ-*.md' 2>/dev/null | head -1)"
  [ -z "$found" ] || fail "$CURRENT_CASE: fixture unexpectedly has markdown REQ file: $found (invalidates AC3 proof)"
}

# ----------------------------------------------------------------------
# Case 1: empty deps (no REQs at all) → exit 0, silent (clean)
# ----------------------------------------------------------------------
CURRENT_CASE="empty-deps-no-reqs"
CASES=$((CASES + 1))
setup_fixture
mkroot
mkur "U" "B" >/dev/null
run_check
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty (clean)"
assert_no_markdown_reqs
teardown_fixture

# ----------------------------------------------------------------------
# Case 2: acyclic linear chain A→B→C (B deps A, C deps B) → exit 0, silent
# ----------------------------------------------------------------------
CURRENT_CASE="acyclic-linear"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
B="$(mkreq "$UR" "B")"
C="$(mkreq "$UR" "C")"
add_dep "$B" "$A"
add_dep "$C" "$B"
run_check
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty (clean)"
assert_not_contains "runtime-cycle" "$CHK_STDOUT" "$CURRENT_CASE no runtime-cycle signal"
assert_no_markdown_reqs
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: direct cycle A→B→A → runtime-cycle diagnosis with the cycle path
# ----------------------------------------------------------------------
CURRENT_CASE="direct-cycle"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
B="$(mkreq "$UR" "B")"
add_dep "$A" "$B"
add_dep "$B" "$A"
run_check
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc (stdout presence, parity with deadlock-check.sh)"
assert_contains "deadlock-detected" "$CHK_STDOUT" "$CURRENT_CASE detected"
assert_contains "signal: runtime-cycle" "$CHK_STDOUT" "$CURRENT_CASE signal"
assert_contains "fingerprint: deadlock:runtime-cycle:" "$CHK_STDOUT" "$CURRENT_CASE fingerprint"
assert_contains "diagnosis:" "$CHK_STDOUT" "$CURRENT_CASE diagnosis label"
# Cycle path in the diagnosis: both endpoints + an arrow.
assert_contains "$A" "$CHK_STDOUT" "$CURRENT_CASE cycle path has $A"
assert_contains "$B" "$CHK_STDOUT" "$CURRENT_CASE cycle path has $B"
assert_contains "→" "$CHK_STDOUT" "$CURRENT_CASE cycle path has arrow"
assert_no_markdown_reqs
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: self-loop A→A → runtime-cycle with "A → A"
# ----------------------------------------------------------------------
CURRENT_CASE="self-loop"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
add_dep "$A" "$A"
run_check
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "signal: runtime-cycle" "$CHK_STDOUT" "$CURRENT_CASE signal"
assert_contains "$A → $A" "$CHK_STDOUT" "$CURRENT_CASE self-loop path"
assert_no_markdown_reqs
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: transitive cycle A→B→C→A → runtime-cycle, full path (all three)
# ----------------------------------------------------------------------
CURRENT_CASE="transitive-cycle"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
B="$(mkreq "$UR" "B")"
C="$(mkreq "$UR" "C")"
add_dep "$A" "$B"
add_dep "$B" "$C"
add_dep "$C" "$A"
run_check
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "signal: runtime-cycle" "$CHK_STDOUT" "$CURRENT_CASE signal"
assert_contains "$A" "$CHK_STDOUT" "$CURRENT_CASE cycle path has $A"
assert_contains "$B" "$CHK_STDOUT" "$CURRENT_CASE cycle path has $B"
assert_contains "$C" "$CHK_STDOUT" "$CURRENT_CASE cycle path has $C"
assert_contains "→" "$CHK_STDOUT" "$CURRENT_CASE cycle path has arrow"
assert_no_markdown_reqs
teardown_fixture

# ----------------------------------------------------------------------
# Case 6: empty deps table but REQs exist → clean
# ----------------------------------------------------------------------
CURRENT_CASE="empty-deps-with-reqs"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
mkreq "$UR" "A" >/dev/null
mkreq "$UR" "B" >/dev/null
run_check
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty (clean)"
assert_no_markdown_reqs
teardown_fixture

# ----------------------------------------------------------------------
# Case 7: parity block shape — a runtime-cycle report carries every field
#         the run loop parses (signal/fingerprint/diagnosis/live-slots/
#         stale-slots/backlog-size/last-commit-age).
# ----------------------------------------------------------------------
CURRENT_CASE="parity-block-fields"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
B="$(mkreq "$UR" "B")"
add_dep "$A" "$B"
add_dep "$B" "$A"
run_check
assert_contains "signal: runtime-cycle"    "$CHK_STDOUT" "$CURRENT_CASE signal"
assert_contains "fingerprint:"             "$CHK_STDOUT" "$CURRENT_CASE fingerprint"
assert_contains "diagnosis:"               "$CHK_STDOUT" "$CURRENT_CASE diagnosis"
assert_contains "live-slots:"              "$CHK_STDOUT" "$CURRENT_CASE live-slots"
assert_contains "stale-slots:"             "$CHK_STDOUT" "$CURRENT_CASE stale-slots"
assert_contains "backlog-size:"            "$CHK_STDOUT" "$CURRENT_CASE backlog-size"
assert_contains "last-commit-age:"         "$CHK_STDOUT" "$CURRENT_CASE last-commit-age"
assert_no_markdown_reqs
teardown_fixture

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------
echo ""
echo "Ran $CASES cases. Failures: $FAILED"
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
