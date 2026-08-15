#!/usr/bin/env bash
# Tests for lib/coverage-rollup.sh
# Plain bash (no bats dependency). Compatible with macOS bash 3.2.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SCRIPT="$LIB_DIR/coverage-rollup.sh"

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

assert_not_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"
  case "$haystack" in
    *"$needle"*) fail "$label: unexpected substring '$needle' in '$haystack'" ;;
  esac
}

setup_fixture() {
  TMP="$(mktemp -d -t coverage-rollup-test.XXXXXX)"
  mkdir -p "$TMP/.do-work/archive" "$TMP/.do-work/working" "$TMP/.do-work/pending"
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
  local layer="${6:-agents}"
  cat > "$path" <<EOF
# $id: Test

**UR:** $ur
**Status:** $status
**Created:** 2026-06-09
**Layer:** $layer
**Closure proof:** $proof
**Files:** agents/run.md
**Depends on:**
EOF
}

# write_req_with_suite adds a `**Suite:**` header line (REQ-263: guards
# against a future consumer duplicating derive-status.sh's marker logic
# instead of delegating to it — see decisions.md 2026-06-12 REQ-239/240).
write_req_with_suite() {
  local path="$1"
  local id="$2"
  local ur="$3"
  local status="$4"
  local proof="$5"
  local suite="$6"
  local layer="${7:-agents}"
  cat > "$path" <<EOF
# $id: Test

**UR:** $ur
**Status:** $status
**Created:** 2026-06-09
**Layer:** $layer
**Closure proof:** $proof
**Suite:** $suite
**Files:** agents/run.md
**Depends on:**
EOF
}

# write_closure <ur> <overall> [closed-count] [gaps-count]
# Writes a minimal UR-NNN/closure.md with the front-matter fields the rollup reads.
write_closure() {
  local ur="$1"
  local overall="$2"
  local closed="${3:-0}"
  local gaps="${4:-0}"
  local dir="$TMP/.do-work/user-requests/$ur"
  mkdir -p "$dir"
  cat > "$dir/closure.md" <<EOF
---
ur: $ur
closed_at: 2026-06-12T14:20:05Z
branch: main
path_units: $((closed + gaps))
verdict_summary:
  closed: $closed
  terminal-mismatch: $gaps
overall: $overall
---

# Closure report — $ur
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
assert_not_contains "pending=" "$OUT" "$CURRENT_CASE no pending field"
assert_contains "unproven_ids=REQ-002,REQ-003" "$OUT" "$CURRENT_CASE ids"
# Additive: an Issue with no path-unit REQs and no closure.md reports closed=n/a,
# and the existing fields are unchanged.
assert_contains "closed=n/a" "$OUT" "$CURRENT_CASE closure column"
teardown_fixture

CURRENT_CASE="fully-proven"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-004-a.md" "REQ-004" "UR-002" "done" "checkpoint:RUN-004 commit:abc"
write_req "$TMP/.do-work/archive/REQ-005-b.md" "REQ-005" "UR-002" "done" "checkpoint:RUN-005 commit:def"
run_script "UR-002"
assert_contains "UR-002 intended=2 proven=2 unproven=0" "$OUT" "$CURRENT_CASE counts"
teardown_fixture

# --- Closure column (REQ-213): end-to-end closure state per Issue ---

# closed=yes: path-unit REQ present, closure.md exists with overall: closed.
CURRENT_CASE="closure-yes"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-010-pu.md" "REQ-010" "UR-010" "done" "checkpoint:RUN-010 commit:abc" "none"
write_req "$TMP/.do-work/archive/REQ-011-impl.md" "REQ-011" "UR-010" "done" "checkpoint:RUN-011 commit:def" "agents"
write_closure "UR-010" "closed" 1 0
run_script "UR-010"
assert_contains "UR-010 intended=2 proven=2 unproven=0" "$OUT" "$CURRENT_CASE counts"
assert_contains "closed=yes" "$OUT" "$CURRENT_CASE closure"
teardown_fixture

# closed=no (gaps): path-unit REQ present, closure.md exists with overall: gaps.
CURRENT_CASE="closure-no-gaps"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-020-pu.md" "REQ-020" "UR-020" "done" "checkpoint:RUN-020 commit:abc" "none"
write_closure "UR-020" "gaps" 0 1
run_script "UR-020"
assert_contains "closed=no" "$OUT" "$CURRENT_CASE closure"
teardown_fixture

# closed=no (absent): path-unit REQ done but no closure.md written yet.
CURRENT_CASE="closure-no-absent"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-030-pu.md" "REQ-030" "UR-030" "done" "checkpoint:RUN-030 commit:abc" "none"
run_script "UR-030"
assert_contains "closed=no" "$OUT" "$CURRENT_CASE closure"
teardown_fixture

# closed=n/a: Issue has no path-unit REQs at all.
CURRENT_CASE="closure-na"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-040-a.md" "REQ-040" "UR-040" "done" "checkpoint:RUN-040 commit:abc" "agents"
run_script "UR-040"
assert_contains "closed=n/a" "$OUT" "$CURRENT_CASE closure"
teardown_fixture

# --- Legacy pending-validation data (UR-039): no derived pending bucket ---

# A legacy Status value in an active scanned directory falls through to
# unproven. The rollup has no pending bucket or output field.
CURRENT_CASE="legacy-pending-validation-is-unproven"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-050-a.md" "REQ-050" "UR-050" "done" "checkpoint:RUN-050 commit:abc"
write_req "$TMP/.do-work/working/REQ-051-legacy.md" "REQ-051" "UR-050" "pending-validation" ""
run_script "UR-050"
assert_contains "UR-050 intended=2 proven=1 unproven=1" "$OUT" "$CURRENT_CASE counts"
assert_contains "unproven_ids=REQ-051" "$OUT" "$CURRENT_CASE ids"
assert_not_contains "pending=" "$OUT" "$CURRENT_CASE no pending field"
teardown_fixture

# A stale .do-work/pending/ directory is ignored by rollup. Upgrade owns
# migrating those files; status tooling must not scan that directory.
CURRENT_CASE="pending-directory-ignored"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-060-a.md" "REQ-060" "UR-060" "done" "checkpoint:RUN-060 commit:abc"
write_req "$TMP/.do-work/pending/REQ-061-stale.md" "REQ-061" "UR-060" "pending-validation" ""
run_script "UR-060"
assert_contains "UR-060 intended=1 proven=1 unproven=0" "$OUT" "$CURRENT_CASE counts"
assert_not_contains "REQ-061" "$OUT" "$CURRENT_CASE stale pending file ignored"
assert_not_contains "pending=" "$OUT" "$CURRENT_CASE no pending field"
teardown_fixture

# A `**Suite:** not-run` REQ (REQ-263) is counted in unproven= and listed in
# unproven_ids= — rollup delegates to derive-status.sh for the marker logic,
# it does not duplicate it.
CURRENT_CASE="suite-not-run-counts-as-unproven"
CASES=$((CASES + 1))
setup_fixture
write_req "$TMP/.do-work/archive/REQ-070-a.md" "REQ-070" "UR-070" "done" "checkpoint:RUN-070 commit:abc"
write_req_with_suite "$TMP/.do-work/archive/REQ-071-marker.md" "REQ-071" "UR-070" "done" "checkpoint:RUN-071 commit:def" "not-run"
run_script "UR-070"
assert_contains "UR-070 intended=2 proven=1 unproven=1" "$OUT" "$CURRENT_CASE counts"
assert_contains "unproven_ids=REQ-071" "$OUT" "$CURRENT_CASE ids"
teardown_fixture

echo ""
echo "coverage-rollup tests: $CASES cases, $FAILED failure(s)"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
