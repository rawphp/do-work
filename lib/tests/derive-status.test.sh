#!/usr/bin/env bash
# Tests for lib/derive-status.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/derive-status.sh"

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

setup_fixture() {
  TMP="$(mktemp -d -t derive-status-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/archive" "$TMP/.do-work/working"
}

teardown_fixture() {
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

write_req() {
  local path="$1"
  local id="$2"
  local status="$3"
  local proof="$4"
  cat > "$path" <<EOF
# $id: Test

**UR:** UR-001
**Status:** $status
**Created:** 2026-06-09
**Layer:** agents
**Closure proof:** $proof
**Files:** agents/run.md
**Depends on:**
EOF
}

run_case() {
  local req_path="$1"
  OUT="$(bash "$SCRIPT" "$req_path")"
  RC=$?
}

CURRENT_CASE="done-with-proof"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-001-done.md" "REQ-001" "done" "checkpoint:RUN-001 commit:abc123"
run_case "$TMP/.do-work/archive/REQ-001-done.md"
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "REQ-001 proven" "$OUT" "$CURRENT_CASE output"
teardown_fixture

CURRENT_CASE="done-without-proof"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-002-done.md" "REQ-002" "done" ""
run_case "$TMP/.do-work/archive/REQ-002-done.md"
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "REQ-002 unproven" "$OUT" "$CURRENT_CASE output"
teardown_fixture

CURRENT_CASE="in-progress-with-proof"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/working/REQ-003-work.md" "REQ-003" "in-progress" "checkpoint:RUN-003 commit:def456"
run_case "$TMP/.do-work/working/REQ-003-work.md"
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "REQ-003 unproven" "$OUT" "$CURRENT_CASE output"
teardown_fixture

# A legacy pending-validation REQ now falls through to unproven. The status no
# longer has its own derived bucket, and an empty proof remains unproven.
CURRENT_CASE="legacy-pending-validation"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/working/REQ-006-park.md" "REQ-006" "pending-validation" ""
run_case "$TMP/.do-work/working/REQ-006-park.md"
assert_eq "0" "$RC" "$CURRENT_CASE rc"
assert_eq "REQ-006 unproven" "$OUT" "$CURRENT_CASE output"
teardown_fixture

echo ""
echo "derive-status tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
