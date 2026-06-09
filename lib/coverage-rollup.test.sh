#!/usr/bin/env bash
# Tests for lib/coverage-rollup.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT="$SCRIPT_DIR/coverage-rollup.sh"

FAILED=0
CASES=0
CURRENT_CASE=""

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
    *) fail "$label: expected substring '$needle' in '$haystack'" ;;
  esac
}

setup_fixture() {
  TMP="$(mktemp -d -t coverage-rollup-test.XXXXXX)"
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
  local ur="$3"
  local status="$4"
  local proof="$5"
  cat > "$path" <<EOF
# $id: Test

**UR:** $ur
**Status:** $status
**Created:** 2026-06-09
**Layer:** agents
**Closure proof:** $proof
**Files:** agents/run.md
**Depends on:**
EOF
}

run_script() {
  local scope="${1:-}"
  if [ -n "$scope" ]; then
    OUT="$(cd "$TMP" && bash "$SCRIPT" "$scope")"
  else
    OUT="$(cd "$TMP" && bash "$SCRIPT")"
  fi
  RC=$?
}

CURRENT_CASE="mixed-proven-unproven"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-001-a.md" "REQ-001" "UR-001" "done" "checkpoint:RUN-001 commit:abc"
write_req "$TMP/.do-work/REQ-002-b.md" "REQ-002" "UR-001" "backlog" ""
write_req "$TMP/.do-work/working/REQ-003-c.md" "REQ-003" "UR-001" "in-progress" "checkpoint:RUN-003 commit:def"
run_script
assert_contains "UR-001 intended=3 proven=1 unproven=2" "$OUT" "$CURRENT_CASE counts"
assert_contains "unproven_ids=REQ-002,REQ-003" "$OUT" "$CURRENT_CASE ids"
teardown_fixture

CURRENT_CASE="fully-proven"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-004-a.md" "REQ-004" "UR-002" "done" "checkpoint:RUN-004 commit:abc"
write_req "$TMP/.do-work/archive/REQ-005-b.md" "REQ-005" "UR-002" "done" "checkpoint:RUN-005 commit:def"
run_script "UR-002"
assert_contains "UR-002 intended=2 proven=2 unproven=0" "$OUT" "$CURRENT_CASE counts"
teardown_fixture

echo ""
echo "coverage-rollup tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0

