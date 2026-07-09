#!/usr/bin/env bash
# Tests for lib/check-deps.sh — pending-only dependency cases.
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.
#
# Covers:
#   (a) archive-only dep → satisfied
#   (b) pending-only dep → reported missing
#   (c) both archive + pending present → satisfied via archive
#   (d) absent from archive → reported missing
#   (e) empty Depends on: → empty stdout, exit 0
#   (f) absent pending/ directory → no error (graceful degradation)

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
CHECKER="$LIB_DIR/check-deps.sh"

FAILED=0
CASES=0
CURRENT_CASE=""
TMP=""

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

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"
  case "$haystack" in
    *"$needle"*) : ;;
    *) fail "$label: expected substring '$needle' in '$haystack'" ;;
  esac
}

assert_not_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"
  case "$haystack" in
    *"$needle"*) fail "$label: did not expect substring '$needle' in '$haystack'" ;;
  esac
}

# Set up a throwaway fixture dir with archive/ and pending/ subdirs.
setup_fixture() {
  TMP="$(mktemp -d -t check-deps-pending-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/archive" "$TMP/.do-work/pending"
}

# Tear down the fixture.
teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
  TMP=""
}

# Write a REQ file with the given Depends on: value.
write_req() {
  local path="$1"
  local id="$2"
  local deps="$3"
  cat > "$path" <<EOF
# $id: Test REQ

**UR:** UR-001
**Status:** backlog
**Created:** 2026-06-12
**Layer:** agents
**Files:** lib/check-deps.sh
**Depends on:** $deps
EOF
}

# Write a stub REQ file (just needs to exist as a matching file).
write_stub() {
  local path="$1"
  local id="$2"
  cat > "$path" <<EOF
# $id: Stub REQ

**UR:** UR-001
**Status:** done
**Created:** 2026-06-12
**Layer:** agents
**Files:** lib/check-deps.sh
**Depends on:**
EOF
}

# Run check-deps.sh from inside the fixture dir so .do-work is found via CWD.
run_checker() {
  local req_path="$1"
  local err_file="$TMP/.stderr.$$"
  local out_file="$TMP/.stdout.$$"
  ( cd "$TMP" && "$CHECKER" "$req_path" > "$out_file" 2> "$err_file" )
  CHK_RC=$?
  CHK_STDOUT="$(cat "$out_file" 2>/dev/null || true)"
  CHK_STDERR="$(cat "$err_file" 2>/dev/null || true)"
  rm -f "$err_file" "$out_file"
}

# -----------------------------------------------------------------------
# Case (a): archive-only dep → satisfied (empty stdout)
# -----------------------------------------------------------------------
CURRENT_CASE="archive-only-satisfied"
CASES=$((CASES + 1))
setup_fixture
write_stub "$TMP/.do-work/archive/REQ-100-done.md" "REQ-100"
write_req  "$TMP/.do-work/REQ-200-target.md" "REQ-200" "REQ-100"
run_checker ".do-work/REQ-200-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty (archive dep satisfied)"
teardown_fixture

# -----------------------------------------------------------------------
# Case (b): pending-only dep → reported missing
# -----------------------------------------------------------------------
CURRENT_CASE="pending-only-missing"
CASES=$((CASES + 1))
setup_fixture
write_stub "$TMP/.do-work/pending/REQ-101-parked.md" "REQ-101"
write_req  "$TMP/.do-work/REQ-201-target.md" "REQ-201" "REQ-101"
run_checker ".do-work/REQ-201-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "REQ-101" "$CHK_STDOUT" "$CURRENT_CASE stdout has missing dep"
teardown_fixture

# -----------------------------------------------------------------------
# Case (c): dep present in both archive and pending → satisfied via archive
# -----------------------------------------------------------------------
CURRENT_CASE="both-archive-and-pending-satisfied"
CASES=$((CASES + 1))
setup_fixture
write_stub "$TMP/.do-work/archive/REQ-102-done.md" "REQ-102"
write_stub "$TMP/.do-work/pending/REQ-102-parked.md" "REQ-102"
write_req  "$TMP/.do-work/REQ-202-target.md" "REQ-202" "REQ-102"
run_checker ".do-work/REQ-202-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty (dep satisfied via archive)"
teardown_fixture

# -----------------------------------------------------------------------
# Case (d): dep absent from archive/ → printed as missing
# -----------------------------------------------------------------------
CURRENT_CASE="absent-from-both-missing"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-203-target.md" "REQ-203" "REQ-103"
run_checker ".do-work/REQ-203-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "REQ-103" "$CHK_STDOUT" "$CURRENT_CASE stdout has missing dep"
teardown_fixture

# -----------------------------------------------------------------------
# Case (e): empty Depends on: → empty stdout, exit 0
# -----------------------------------------------------------------------
CURRENT_CASE="empty-deps"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/REQ-204-target.md" "REQ-204" ""
run_checker ".do-work/REQ-204-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "" "$CHK_STDOUT" "$CURRENT_CASE stdout empty"
teardown_fixture

# -----------------------------------------------------------------------
# Case (f): pending/ directory absent → no error, archive-only logic applies
# -----------------------------------------------------------------------
CURRENT_CASE="no-pending-dir-graceful"
CASES=$((CASES + 1))
setup_fixture
# Remove the pending/ dir entirely
rm -rf "$TMP/.do-work/pending"
write_stub "$TMP/.do-work/archive/REQ-104-done.md" "REQ-104"
write_req  "$TMP/.do-work/REQ-205-target.md" "REQ-205" "REQ-104, REQ-105"
run_checker ".do-work/REQ-205-target.md"
assert_eq "0" "$CHK_RC" "$CURRENT_CASE rc"
assert_eq "REQ-105" "$CHK_STDOUT" "$CURRENT_CASE stdout has only missing dep"
assert_eq "" "$CHK_STDERR" "$CURRENT_CASE no error on stderr"
teardown_fixture

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "Ran $CASES cases. Failures: $FAILED"
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
