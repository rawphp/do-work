#!/usr/bin/env bash
# Tests for dw-db cycle-check (lib/dw-db.sh) — sqlite whole-graph cycle detection.
# Plain bash (no bats dependency). Exit non-zero on first failure.
# Compatible with macOS bash 3.2.
#
# Acceptance criteria (REQ-017):
#   - acyclic DB → exit 0, silent.
#   - A→B→A → exit 1, stdout names both ids.
#   - transitive A→B→C→A → exit 1, full path.
#   - self-loop A→A → exit 1, prints "A → A".
#   - empty deps → exit 0.
#   - cross-Issue cycle (UR-X ↔ UR-Y) → exit 1 (whole graph).
#   - UR report-filter: cycle-check <root> UR-X reports only cycles involving
#     UR-X, yet STILL detects cross-Issue cycles; does NOT report unrelated Issues.
#   - hypothetical-edge (--add): "would adding edge(s) X create a cycle?" without
#     persisting → yes on would-be-cycle, no on safe edge; DB unchanged after.
#
# Cycles are built by direct INSERT into the deps junction (NOT via
# set-blocked-by, which rejects cycles after its own REQ lands).

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
  TMP="$(mktemp -d -t cycle-check-db-test.XXXXXX)"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

# Create UR + REQs. Each REQ var passed by name is assigned its real slug.
# Usage: mkroot; mkur "Title" "Brief"   → echoes Issue slug
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

# run_check <args...> — runs cycle-check against $TMP; sets CHK_RC / CHK_STDOUT.
run_check() {
  local out_file="$TMP/.stdout.$$"
  local err_file="$TMP/.stderr.$$"
  bash "$DWDB" cycle-check "$TMP" "$@" >"$out_file" 2>"$err_file"
  CHK_RC=$?
  CHK_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  CHK_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$out_file" "$err_file"
}

# ----------------------------------------------------------------------
# Case 1: empty deps (no REQs at all) → exit 0, silent
# ----------------------------------------------------------------------
CURRENT_CASE="empty-deps-no-reqs"
CASES=$((CASES + 1))
setup_fixture
mkroot
mkur "U" "B" >/dev/null
run_check
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty"
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
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty"
teardown_fixture

# ----------------------------------------------------------------------
# Case 3: direct cycle A→B→A → exit 1, stdout names both ids + arrow
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
assert_eq "1" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "$A" "$CHK_STDOUT" "$CURRENT_CASE has $A"
assert_contains "$B" "$CHK_STDOUT" "$CURRENT_CASE has $B"
assert_contains "→" "$CHK_STDOUT" "$CURRENT_CASE has arrow"
teardown_fixture

# ----------------------------------------------------------------------
# Case 4: transitive cycle A→B→C→A → exit 1, full path (all three ids)
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
assert_eq "1" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "$A" "$CHK_STDOUT" "$CURRENT_CASE has $A"
assert_contains "$B" "$CHK_STDOUT" "$CURRENT_CASE has $B"
assert_contains "$C" "$CHK_STDOUT" "$CURRENT_CASE has $C"
assert_contains "→" "$CHK_STDOUT" "$CURRENT_CASE has arrow"
teardown_fixture

# ----------------------------------------------------------------------
# Case 5: self-loop A→A → exit 1, prints "A → A"
# ----------------------------------------------------------------------
CURRENT_CASE="self-loop"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
add_dep "$A" "$A"
run_check
assert_eq "1" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "$A → $A" "$CHK_STDOUT" "$CURRENT_CASE prints self-loop path"
teardown_fixture

# ----------------------------------------------------------------------
# Case 6: empty deps table but REQs exist → exit 0
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
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty"
teardown_fixture

# ----------------------------------------------------------------------
# Case 7: cross-Issue cycle (UR-X REQ A ↔ UR-Y REQ B) → exit 1 (whole graph)
# ----------------------------------------------------------------------
CURRENT_CASE="cross-ur-cycle-whole-graph"
CASES=$((CASES + 1))
setup_fixture
mkroot
UX="$(mkur "UX" "B")"
UY="$(mkur "UY" "B")"
A="$(mkreq "$UX" "A")"
B="$(mkreq "$UY" "B")"
add_dep "$A" "$B"
add_dep "$B" "$A"
run_check
assert_eq "1" "$CHK_RC" "$CURRENT_CASE rc"
assert_contains "$A" "$CHK_STDOUT" "$CURRENT_CASE has $A"
assert_contains "$B" "$CHK_STDOUT" "$CURRENT_CASE has $B"
teardown_fixture

# ----------------------------------------------------------------------
# Case 8: UR report-filter detects cross-Issue cycle when filtered to either UR;
#         an unrelated UR sees nothing.
# ----------------------------------------------------------------------
CURRENT_CASE="ur-filter-cross-ur-detected"
CASES=$((CASES + 1))
setup_fixture
mkroot
UX="$(mkur "UX" "B")"
UY="$(mkur "UY" "B")"
UZ="$(mkur "UZ" "B")"
A="$(mkreq "$UX" "A")"
B="$(mkreq "$UY" "B")"
add_dep "$A" "$B"
add_dep "$B" "$A"
run_check "$UX"
assert_eq "1" "$CHK_RC" "$CURRENT_CASE rc under $UX"
assert_contains "$A" "$CHK_STDOUT" "$CURRENT_CASE has $A under $UX"
run_check "$UY"
assert_eq "1" "$CHK_RC" "$CURRENT_CASE rc under $UY"
run_check "$UZ"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc under unrelated $UZ"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE silent under unrelated $UZ"
teardown_fixture

# ----------------------------------------------------------------------
# Case 9: UR report-filter does NOT narrow the subgraph. UR-P has its own
#         internal cycle; UR-Q is acyclic. Filtering to UR-Q reports nothing,
#         filtering to UR-P reports the cycle.
# ----------------------------------------------------------------------
CURRENT_CASE="ur-filter-skips-unrelated-cycle"
CASES=$((CASES + 1))
setup_fixture
mkroot
UP="$(mkur "UP" "B")"
UQ="$(mkur "UQ" "B")"
PA="$(mkreq "$UP" "PA")"
PB="$(mkreq "$UP" "PB")"
QA="$(mkreq "$UQ" "QA")"
QB="$(mkreq "$UQ" "QB")"
add_dep "$PA" "$PB"
add_dep "$PB" "$PA"          # cycle inside UR-P
add_dep "$QB" "$QA"          # acyclic edge inside UR-Q
run_check "$UQ"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc under $UQ (unrelated cycle hidden)"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE silent under $UQ"
run_check "$UP"
assert_eq "1" "$CHK_RC" "$CURRENT_CASE rc under $UP"
assert_contains "$PA" "$CHK_STDOUT" "$CURRENT_CASE has PA under $UP"
teardown_fixture

# ----------------------------------------------------------------------
# Case 10: hypothetical-edge --add. Base graph A→B is acyclic.
#   --add B A  → would close A→B→A → exit 1.
#   --add A C  → safe leaf → exit 0.
#   plain cycle-check afterwards → still acyclic (nothing persisted).
# ----------------------------------------------------------------------
CURRENT_CASE="hypothetical-add-edge"
CASES=$((CASES + 1))
setup_fixture
mkroot
UR="$(mkur "U" "B")"
A="$(mkreq "$UR" "A")"
B="$(mkreq "$UR" "B")"
C="$(mkreq "$UR" "C")"
add_dep "$A" "$B"             # A→B acyclic
run_check --add "$B" "$A"
assert_eq "1" "$CHK_RC" "$CURRENT_CASE --add B A would-cycle rc"
assert_contains "$A" "$CHK_STDOUT" "$CURRENT_CASE --add B A names A"
assert_contains "$B" "$CHK_STDOUT" "$CURRENT_CASE --add B A names B"
run_check --add "$A" "$C"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE --add A C safe rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE --add A C silent"
# Nothing persisted by --add:
run_check
assert_eq "0" "$CHK_RC" "$CURRENT_CASE plain check still acyclic after --add"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE plain check silent after --add"
teardown_fixture

# ----------------------------------------------------------------------
# Case 11: hypothetical --add combined with UR report-filter.
#   Base A(ur-X)→B(ur-X) acyclic. --add B A under filter UR-X → cycle reported.
# ----------------------------------------------------------------------
CURRENT_CASE="hypothetical-add-with-filter"
CASES=$((CASES + 1))
setup_fixture
mkroot
UX="$(mkur "UX" "B")"
UZ="$(mkur "UZ" "B")"
A="$(mkreq "$UX" "A")"
B="$(mkreq "$UX" "B")"
add_dep "$A" "$B"
run_check "$UX" --add "$B" "$A"
assert_eq "1" "$CHK_RC" "$CURRENT_CASE filter UX + add cycle rc"
run_check "$UZ" --add "$B" "$A"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE unrelated filter UZ + add cycle hidden"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE silent under unrelated filter"
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
