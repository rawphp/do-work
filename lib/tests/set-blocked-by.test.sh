#!/usr/bin/env bash
# Tests for dw-db set-blocked-by (lib/dw-db.sh) — write-time cycle rejection.
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.
#
# Acceptance criteria (REQ-018):
#   - acyclic dep (incl. on a third REQ) → succeeds, commits.
#   - direct cycle A→B then B→A → 2nd exits non-zero, prints cycle path,
#     and REQ-B's deps are unchanged (rollback held — DELETE+INSERT never
#     committed).
#   - self-loop A→A → non-zero, prints "A → A", nothing committed.
#   - clearing deps (set-blocked-by A "") → succeeds, cannot create a cycle.
#   - the cycle check runs INSIDE the same BEGIN IMMEDIATE tx as the
#     DELETE+INSERT — demonstrated by a rejected write leaving the REQ's
#     PRIOR committed deps intact (the in-tx DELETE was rolled back).
#   - sequential double-insert forming a cycle → second rejected.
#
# All edges are built via `dw-db set-blocked-by` itself (the op under test).

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

setup_fixture() {
  TMP="$(mktemp -d -t set-blocked-by-test.XXXXXX)"
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

# All dep slugs of a REQ (by slug → id subquery), regardless of status.
deps_of() {
  local rs="$1"
  local db="$TMP/.do-work/work.db"
  sqlite3 "$db" "SELECT r2.slug FROM deps d \
JOIN reqs r1 ON r1.id = d.req_id \
JOIN reqs r2 ON r2.id = d.depends_on_req_id \
WHERE r1.slug='$rs' ORDER BY r2.slug;" | paste -sd' ' -
}

# run_sbb <REQ> [dep slugs...] — runs set-blocked-by against $TMP.
# Sets SBB_RC / SBB_OUT / SBB_ERR.
run_sbb() {
  local out_file="$TMP/.out.$$"
  local err_file="$TMP/.err.$$"
  bash "$DWDB" set-blocked-by "$TMP" "$@" >"$out_file" 2>"$err_file"
  SBB_RC=$?
  SBB_OUT="$(cat "$out_file" 2>/dev/null || true)"
  SBB_ERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$out_file" "$err_file"
}

# ----------------------------------------------------------------------
# Case 1: acyclic single dep A→B → exit 0, A deps == [B]
# ----------------------------------------------------------------------
CURRENT_CASE="acyclic-single-dep"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
B="$(mkreq "$UR" "B")"
run_sbb "$A" "$B"
assert_eq "0" "$SBB_RC" "$CURRENT_CASE rc"
assert_eq "$B" "$(deps_of "$A")" "$CURRENT_CASE A deps == [B]"
teardown_fixture

# ----------------------------------------------------------------------
# Case 2: acyclic chain A→B, B→C (dep on a third REQ) → both exit 0
# ----------------------------------------------------------------------
CURRENT_CASE="acyclic-chain-third-req"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
B="$(mkreq "$UR" "B")"
C="$(mkreq "$UR" "C")"
run_sbb "$A" "$B"
assert_eq "0" "$SBB_RC" "$CURRENT_CASE A→B rc"
run_sbb "$B" "$C"
assert_eq "0" "$SBB_RC" "$CURRENT_CASE B→C rc"
assert_eq "$B" "$(deps_of "$A")" "$CURRENT_CASE A deps"
assert_eq "$C" "$(deps_of "$B")" "$CURRENT_CASE B deps"
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: self-loop A→A → non-zero, prints "A → A", nothing committed
# ----------------------------------------------------------------------
CURRENT_CASE="self-loop-rejected"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
run_sbb "$A" "$A"
[ "$SBB_RC" -ne 0 ] || fail "$CURRENT_CASE expected non-zero rc, got 0"
assert_contains "$A → $A" "$SBB_ERR" "$CURRENT_CASE prints self-loop path"
assert_eq "" "$(deps_of "$A")" "$CURRENT_CASE nothing committed"
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: direct cycle A→B then B→A → 2nd non-zero, names cycle,
#         REQ-B deps unchanged (rollback held, B had no prior deps).
# ----------------------------------------------------------------------
CURRENT_CASE="direct-cycle-rejected"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
B="$(mkreq "$UR" "B")"
run_sbb "$A" "$B"
assert_eq "0" "$SBB_RC" "$CURRENT_CASE A→B rc"
run_sbb "$B" "$A"
[ "$SBB_RC" -ne 0 ] || fail "$CURRENT_CASE expected non-zero rc, got 0"
assert_contains "$A" "$SBB_ERR" "$CURRENT_CASE cycle names A"
assert_contains "$B" "$SBB_ERR" "$CURRENT_CASE cycle names B"
assert_contains "→" "$SBB_ERR" "$CURRENT_CASE cycle has arrow"
assert_eq "" "$(deps_of "$B")" "$CURRENT_CASE B deps unchanged (rollback)"
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: cycle check runs INSIDE the BEGIN IMMEDIATE tx. B already deps C
#         (committed). A→B committed. Now set-blocked-by B "A" would form
#         A→B→A → rejected, AND the in-tx DELETE of B→C is rolled back so
#         B STILL deps C. This proves the check+write share one transaction.
# ----------------------------------------------------------------------
CURRENT_CASE="in-tx-rollback-preserves-prior-deps"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
B="$(mkreq "$UR" "B")"
C="$(mkreq "$UR" "C")"
run_sbb "$B" "$C"
assert_eq "0" "$SBB_RC" "$CURRENT_CASE B→C rc"
run_sbb "$A" "$B"
assert_eq "0" "$SBB_RC" "$CURRENT_CASE A→B rc"
run_sbb "$B" "$A"
[ "$SBB_RC" -ne 0 ] || fail "$CURRENT_CASE expected non-zero rc, got 0"
assert_contains "$A" "$SBB_ERR" "$CURRENT_CASE cycle names A"
assert_contains "$B" "$SBB_ERR" "$CURRENT_CASE cycle names B"
assert_eq "$C" "$(deps_of "$B")" "$CURRENT_CASE B still deps C (tx rollback)"
teardown_fixture

# ----------------------------------------------------------------------
# Case 6: clearing deps (set-blocked-by A "") → exit 0, A deps empty,
#         and clearing cannot create a cycle.
# ----------------------------------------------------------------------
CURRENT_CASE="clearing-deps"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
B="$(mkreq "$UR" "B")"
run_sbb "$A" "$B"
assert_eq "0" "$SBB_RC" "$CURRENT_CASE A→B rc"
assert_eq "$B" "$(deps_of "$A")" "$CURRENT_CASE A deps == [B] before clear"
run_sbb "$A" ""
assert_eq "0" "$SBB_RC" "$CURRENT_CASE clear rc"
assert_eq "" "$(deps_of "$A")" "$CURRENT_CASE A deps empty after clear"
teardown_fixture

# ----------------------------------------------------------------------
# Case 7: transitive cycle A→B→C, then C→A closes the loop → rejected,
#         C deps unchanged. Also sequential double-insert: after A→B→C is
#         committed, the cycle-forming C→A is the "second" insert → rejected.
# ----------------------------------------------------------------------
CURRENT_CASE="transitive-cycle-rejected"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
B="$(mkreq "$UR" "B")"
C="$(mkreq "$UR" "C")"
run_sbb "$A" "$B"
assert_eq "0" "$SBB_RC" "$CURRENT_CASE A→B rc"
run_sbb "$B" "$C"
assert_eq "0" "$SBB_RC" "$CURRENT_CASE B→C rc"
run_sbb "$C" "$A"
[ "$SBB_RC" -ne 0 ] || fail "$CURRENT_CASE expected non-zero rc, got 0"
assert_contains "$A" "$SBB_ERR" "$CURRENT_CASE cycle names A"
assert_contains "$C" "$SBB_ERR" "$CURRENT_CASE cycle names C"
assert_eq "" "$(deps_of "$C")" "$CURRENT_CASE C deps unchanged (rollback)"
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
